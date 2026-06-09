module TelegramAccount
  # Starts the TDLib client for a Channel::TelegramAccount.
  # The job itself is short-lived; TDLib's own background threads keep running.
  # Enqueued on channel creation and on Sidekiq startup for all ready channels.
  class MessageListenerJob < ApplicationJob
    queue_as :default

    def perform(channel_id)
      channel = Channel::TelegramAccount.find_by(id: channel_id)

      unless channel
        Rails.logger.warn("TelegramAccount::MessageListenerJob: channel #{channel_id} not found")
        return
      end

      unless channel.account.active?
        Rails.logger.warn("TelegramAccount::MessageListenerJob: account #{channel.account_id} inactive")
        return
      end

      TelegramAccount::ClientManager.start(channel)
      Rails.logger.info("TelegramAccount::MessageListenerJob: client started for channel #{channel_id}")
    end
  end
end
