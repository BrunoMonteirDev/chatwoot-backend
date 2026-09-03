class AddMetaCoexistenceOffboardedAtToChannelWhatsapp < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsapp, :meta_coexistence_offboarded_at, :datetime
  end
end
