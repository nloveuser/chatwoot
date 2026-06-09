module TelegramAccount
  class IncomingMessageService
    pattr_initialize [:channel!, :tdlib_message!]

    def perform
      # Only handle private chats (positive chat_id = user DM)
      return unless private_chat?
      return if duplicate?

      set_contact
      set_conversation
      create_message
    end

    private

    def private_chat?
      # In TDLib: private chat IDs are positive; group/channel IDs are negative
      tdlib_message['chat_id'].to_i.positive?
    end

    def duplicate?
      source = tdlib_message['id'].to_s
      channel.inbox.messages.exists?(source_id: source)
    end

    def sender_user_id
      tdlib_message.dig('sender_id', 'user_id').to_i
    end

    def chat_id
      tdlib_message['chat_id'].to_i
    end

    def set_contact
      user_info = fetch_user_info
      name = [user_info['first_name'], user_info['last_name']].compact.join(' ').presence || "TG#{sender_user_id}"
      username = user_info.dig('usernames', 'active_usernames', 0)

      contact_inbox = ::ContactInboxWithContactBuilder.new(
        source_id: sender_user_id.to_s,
        inbox: channel.inbox,
        contact_attributes: {
          name: name,
          additional_attributes: {
            social_telegram_user_id:   sender_user_id,
            social_telegram_user_name: username
          }
        }
      ).perform

      @contact_inbox = contact_inbox
      @contact       = contact_inbox.contact
    end

    def set_conversation
      @conversation = @contact_inbox.conversations
                                    .where.not(status: :resolved)
                                    .last

      return if @conversation

      @conversation = ::Conversation.create!(
        account_id:            channel.account_id,
        inbox_id:              channel.inbox.id,
        contact_id:            @contact.id,
        contact_inbox_id:      @contact_inbox.id,
        additional_attributes: { telegram_chat_id: chat_id }
      )
    end

    def create_message
      content = extract_text

      @conversation.messages.create!(
        content:      content,
        account_id:   channel.account_id,
        inbox_id:     channel.inbox.id,
        message_type: :incoming,
        sender:       @contact,
        source_id:    tdlib_message['id'].to_s
      )
    end

    def extract_text
      # Text message
      text = tdlib_message.dig('content', 'text', 'text')
      return text if text.present?

      # Caption on media
      caption = tdlib_message.dig('content', 'caption', 'text')
      return caption if caption.present?

      # Sticker description
      sticker = tdlib_message.dig('content', 'sticker', 'emoji')
      return sticker if sticker.present?

      nil
    end

    def fetch_user_info
      client = TelegramAccount::ClientManager.get(channel.id)
      return {} unless client

      # td_execute is synchronous only for certain methods; getUser is async.
      # We make it synchronous by using a Mutex + ConditionVariable.
      result = {}
      done   = false
      lock   = Mutex.new
      cv     = ConditionVariable.new

      client.request({ '@type' => 'getUser', 'user_id' => sender_user_id })
      client.on('user') do |update|
        next unless update['id'].to_i == sender_user_id

        lock.synchronize do
          result = update
          done   = true
          cv.signal
        end
      end

      lock.synchronize { cv.wait(lock, 3) unless done }
      result
    rescue StandardError
      {}
    end
  end
end
