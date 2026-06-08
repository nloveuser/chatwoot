class Channel::TelegramAccount < ApplicationRecord
  include Channelable

  self.table_name = 'channel_telegram_account'
  EDITABLE_ATTRS = %i[gateway_url webhook_id].freeze

  validates :gateway_url, presence: true
  validates :webhook_id, presence: true, uniqueness: true

  def name
    'TelegramAccount'
  end

  def webhook_endpoint
    "#{gateway_url.chomp('/')}/chatwoot/webhook/#{webhook_id}"
  end
end
