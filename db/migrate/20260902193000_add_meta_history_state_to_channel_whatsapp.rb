class AddMetaHistoryStateToChannelWhatsapp < ActiveRecord::Migration[7.1]
  def change
    change_table :channel_whatsapp, bulk: true do |t|
      t.string :meta_history_status, null: false, default: 'not_eligible'
      t.datetime :meta_history_started_at
      t.datetime :meta_history_completed_at
      t.integer :meta_history_progress
      t.string :meta_history_error
      t.string :meta_history_last_chunk
      t.boolean :meta_history_action_available, null: false, default: false
      t.boolean :meta_history_subscription_available, null: false, default: false
    end
  end
end
