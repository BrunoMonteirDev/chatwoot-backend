class AddOperationalStateToChannelWhatsapp < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsapp, :meta_connection_status, :string, null: false, default: 'connected'
    add_column :channel_whatsapp, :meta_connection_last_checked_at, :datetime
    add_column :channel_whatsapp, :meta_connection_last_changed_at, :datetime
    add_column :channel_whatsapp, :meta_connection_last_error, :string, limit: 500
    add_column :channel_whatsapp, :meta_account_update_event, :string, limit: 100
    add_column :channel_whatsapp, :meta_account_update_at, :datetime
  end
end
