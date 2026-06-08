class ReplaceChannelTelegramAccount < ActiveRecord::Migration[7.1]
  def up
    drop_table :channel_telegram_account if table_exists?(:channel_telegram_account)

    create_table :channel_telegram_account do |t|
      t.integer :account_id,         null: false
      t.integer :api_id,             null: false
      t.string  :api_hash,           null: false
      t.string  :phone_number,       null: false
      t.string  :auth_state,         null: false, default: 'pending'
      t.string  :session_directory
      t.string  :error_message
      t.timestamps
    end

    add_index :channel_telegram_account, :phone_number, unique: true
  end

  def down
    drop_table :channel_telegram_account
  end
end
