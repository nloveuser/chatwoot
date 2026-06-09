require 'tdlib_client'

# Manages TDLib client instances for all Channel::TelegramAccount channels.
# Lives in the Sidekiq process; clients run until the process exits.
module TelegramAccount
  class ClientManager
    TDLIB_VERSION = '1.0'

    @clients = {}
    @lock    = Mutex.new

    class << self
      # Start (or return existing) TDLib client for a channel.
      def start(channel)
        @lock.synchronize do
          existing = @clients[channel.id]
          return existing if existing&.alive?

          client = build_client(channel)
          @clients[channel.id] = client
          client
        end
      end

      def get(channel_id)
        @lock.synchronize { @clients[channel_id] }
      end

      def stop(channel_id)
        @lock.synchronize do
          client = @clients.delete(channel_id)
          client&.close
        end
      end

      def stop_all
        @lock.synchronize do
          @clients.each_value(&:close)
          @clients.clear
        end
      end

      # Called from controller after user submits the Telegram auth code.
      def submit_code(channel_id, code)
        client = get(channel_id)
        return false unless client

        client.request({
          '@type' => 'checkAuthenticationCode',
          'code'  => code.to_s
        })
        true
      end

      # Called from controller after user submits the 2FA password.
      def submit_password(channel_id, password)
        client = get(channel_id)
        return false unless client

        client.request({
          '@type'    => 'checkAuthenticationPassword',
          'password' => password.to_s
        })
        true
      end

      private

      def build_client(channel)
        client = TdlibClient.new
        register_handlers(client, channel)
        bootstrap(client, channel)
        client
      end

      def bootstrap(client, channel)
        # Step 1: set TDLib parameters
        client.request({
          '@type'                  => 'setTdlibParameters',
          'database_directory'     => channel.session_path,
          'files_directory'        => channel.files_path,
          'use_file_database'      => true,
          'use_chat_info_database' => true,
          'use_message_database'   => true,
          'use_secret_chats'       => false,
          'api_id'                 => channel.api_id.to_i,
          'api_hash'               => channel.api_hash,
          'system_language_code'   => 'en',
          'device_model'           => 'Chatwoot',
          'application_version'    => TDLIB_VERSION,
          'enable_storage_optimizer' => true
        })
      end

      def register_handlers(client, channel)
        client.on('updateAuthorizationState') do |update|
          handle_auth_state(client, channel.id, update['authorization_state'])
        end

        client.on('updateNewMessage') do |update|
          msg = update['message']
          next if msg['is_outgoing']

          TelegramAccount::ProcessIncomingMessageJob.perform_later(channel.id, msg)
        end

        client.on('updateConnectionState') do |update|
          state = update.dig('state', '@type')
          Rails.logger.info("TelegramAccount[#{channel.id}] connection: #{state}")
        end
      end

      def handle_auth_state(client, channel_id, auth_state)
        return unless auth_state

        channel = Channel::TelegramAccount.find_by(id: channel_id)
        return unless channel

        case auth_state['@type']
        when 'authorizationStateWaitPhoneNumber'
          channel.update_column(:auth_state, 'pending')
          client.request({
            '@type'        => 'setAuthenticationPhoneNumber',
            'phone_number' => channel.phone_number,
            'settings'     => { '@type' => 'phoneNumberAuthenticationSettings',
                                'allow_flash_call' => false,
                                'is_current_phone_number' => false,
                                'allow_sms_retriever_api' => false }
          })

        when 'authorizationStateWaitCode'
          channel.update_column(:auth_state, 'wait_code')

        when 'authorizationStateWaitPassword'
          channel.update_column(:auth_state, 'wait_password')

        when 'authorizationStateReady'
          channel.update_column(:auth_state, 'ready')
          Rails.logger.info("TelegramAccount[#{channel_id}] auth ready")

        when 'authorizationStateLoggingOut', 'authorizationStateClosed'
          channel.update_columns(auth_state: 'error',
                                 error_message: 'Session closed or logged out')
          stop(channel_id)

        when 'authorizationStateClosing'
          # do nothing, wait for Closed
        end
      end
    end
  end
end
