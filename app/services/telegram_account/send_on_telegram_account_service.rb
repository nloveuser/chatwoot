module TelegramAccount
  class SendOnTelegramAccountService < Base::SendOnChannelService
    private

    def channel_class
      Channel::TelegramAccount
    end

    def perform_reply
      client = TelegramAccount::ClientManager.get(channel.id)
      unless client&.alive?
        mark_failed('TDLib client not running for this channel')
        return
      end

      chat_id = message.conversation.additional_attributes['telegram_chat_id']
      unless chat_id
        mark_failed('No telegram_chat_id in conversation attributes')
        return
      end

      client.request(build_send_message(chat_id.to_i))
    end

    def build_send_message(chat_id)
      {
        '@type'   => 'sendMessage',
        'chat_id' => chat_id,
        'input_message_content' => {
          '@type' => 'inputMessageText',
          'text'  => {
            '@type' => 'formattedText',
            'text'  => message.content.to_s
          }
        }
      }
    end

    def mark_failed(reason)
      message.update!(
        external_error: reason,
        status:         :failed
      )
    end
  end
end
