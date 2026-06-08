class Channel::TelegramAccount < ApplicationRecord
  include Channelable

  self.table_name = 'channel_telegram_account'
  EDITABLE_ATTRS = %i[api_id api_hash phone_number].freeze

  AUTH_STATES = %w[pending wait_code wait_password ready error].freeze

  validates :api_id,       presence: true
  validates :api_hash,     presence: true
  validates :phone_number, presence: true, uniqueness: true
  validates :auth_state,   inclusion: { in: AUTH_STATES }

  after_create  :provision_session_directory
  after_create  :start_tdlib_client
  after_destroy :cleanup_session_directory

  def name
    'TelegramAccount'
  end

  def session_path
    session_directory.presence ||
      Rails.root.join('storage', 'telegram_sessions', id.to_s).to_s
  end

  def files_path
    File.join(session_path, 'files')
  end

  def ready?
    auth_state == 'ready'
  end

  private

  def start_tdlib_client
    TelegramAccount::MessageListenerJob.perform_later(id)
  end

  def provision_session_directory
    dir = Rails.root.join('storage', 'telegram_sessions', id.to_s).to_s
    FileUtils.mkdir_p(dir)
    FileUtils.mkdir_p(File.join(dir, 'files'))
    update_column(:session_directory, dir)
  end

  def cleanup_session_directory
    FileUtils.rm_rf(session_path) if session_directory.present?
  end
end
