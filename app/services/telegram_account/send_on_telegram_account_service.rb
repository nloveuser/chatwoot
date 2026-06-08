class TelegramAccount::SendOnTelegramAccountService < Base::SendOnChannelService
  private

  def channel_class
    Channel::TelegramAccount
  end

  def perform_reply
    return if message.content.blank? && message.attachments.blank?

    response = HTTParty.post(
      channel.webhook_endpoint,
      body: build_payload.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 10
    )

    unless response.success?
      message.update!(
        external_error: "Gateway error: #{response.code}",
        status: :failed
      )
    end
  end

  def build_payload
    contact = message.conversation.contact
    {
      event: 'message_created',
      message_type: 'outgoing',
      content: message.content,
      private: false,
      conversation: {
        meta: {
          channel: 'telegram',
          sender: {
            phone_number: contact.phone_number,
            additional_attributes: contact.additional_attributes,
            custom_attributes: contact.custom_attributes
          }
        }
      }
    }
  end
end
