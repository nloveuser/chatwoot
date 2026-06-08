module TelegramAccount
  # Processes a raw TDLib message object and creates Chatwoot contact/conversation/message.
  class ProcessIncomingMessageJob < ApplicationJob
    queue_as :default

    def perform(channel_id, tdlib_message)
      channel = Channel::TelegramAccount.find_by(id: channel_id)
      return unless channel&.account&.active?

      TelegramAccount::IncomingMessageService.new(
        channel:        channel,
        tdlib_message:  tdlib_message.with_indifferent_access
      ).perform
    end
  end
end
