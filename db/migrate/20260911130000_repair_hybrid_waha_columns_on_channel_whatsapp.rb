class RepairHybridWahaColumnsOnChannelWhatsapp < ActiveRecord::Migration[7.1]
  def up
    add_column :channel_whatsapp, :hybrid_enabled, :boolean, null: false, default: false unless column_exists?(:channel_whatsapp, :hybrid_enabled)
    add_column :channel_whatsapp, :hybrid_waha_session, :string unless column_exists?(:channel_whatsapp, :hybrid_waha_session)
    unless column_exists?(:channel_whatsapp, :out_of_window_strategy)
      add_column :channel_whatsapp, :out_of_window_strategy, :string, null: false, default: 'template'
    end
    unless column_exists?(:channel_whatsapp, :meta_failure_strategy)
      add_column :channel_whatsapp, :meta_failure_strategy, :string, null: false, default: 'block'
    end
    return if index_exists?(:channel_whatsapp, :hybrid_waha_session, name: 'index_channel_whatsapp_on_hybrid_waha_session')

    add_index(
      :channel_whatsapp,
      :hybrid_waha_session,
      unique: true,
      where: 'hybrid_waha_session IS NOT NULL',
      name: 'index_channel_whatsapp_on_hybrid_waha_session'
    )
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'The original hybrid WAHA migration owns these columns'
  end
end
