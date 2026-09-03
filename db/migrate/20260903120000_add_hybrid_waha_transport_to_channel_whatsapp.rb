class AddHybridWahaTransportToChannelWhatsapp < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsapp, :hybrid_enabled, :boolean, null: false, default: false
    add_column :channel_whatsapp, :hybrid_waha_session, :string
    add_column :channel_whatsapp, :out_of_window_strategy, :string, null: false, default: 'template'
    add_column :channel_whatsapp, :meta_failure_strategy, :string, null: false, default: 'block'
    add_index :channel_whatsapp, :hybrid_waha_session, unique: true, where: 'hybrid_waha_session IS NOT NULL', name: 'index_channel_whatsapp_on_hybrid_waha_session'
  end
end
