class CreateChannelTelegramAccount < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_telegram_account do |t|
      t.integer :account_id, null: false
      t.string :gateway_url, null: false
      t.string :webhook_id, null: false
      t.timestamps
    end

    add_index :channel_telegram_account, :webhook_id, unique: true
  end
end
