class AddEnabledToDashboardApps < ActiveRecord::Migration[7.1]
  def change
    add_column :dashboard_apps, :enabled, :boolean, default: true, null: false
    add_index :dashboard_apps, [:account_id, :enabled]
  end
end
