class AddPermissionProfiles < ActiveRecord::Migration[7.0]
  def change
    create_table :permission_profiles do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description
      t.text :inbox_permissions, array: true, default: [], null: false
      t.text :system_permissions, array: true, default: [], null: false
      t.boolean :default, null: false, default: false
      t.timestamps
    end
    add_index :permission_profiles, [:account_id, :name], unique: true
    add_reference :account_users, :permission_profile, foreign_key: true
    add_reference :inbox_members, :permission_profile, foreign_key: true
  end
end
