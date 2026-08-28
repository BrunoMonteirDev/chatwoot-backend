class SeparatePermissionProfileKinds < ActiveRecord::Migration[7.0]
  class Profile < ApplicationRecord
    self.table_name = 'permission_profiles'
  end

  def up
    add_column :permission_profiles, :kind, :string, null: false, default: 'inbox'
    add_index :permission_profiles, [:account_id, :kind]

    Profile.reset_column_information
    Profile.where(default: true).find_each do |profile|
      next if Array(profile.system_permissions).empty?

      Profile.find_or_create_by!(account_id: profile.account_id, kind: 'system', default: true) do |system_profile|
        system_profile.name = 'Acesso básico do sistema'
        system_profile.description = 'Acesso padrão aos recursos gerais da conta.'
        system_profile.inbox_permissions = []
        system_profile.system_permissions = profile.system_permissions
      end
      profile.update_columns(system_permissions: [])
    end

    execute <<~SQL.squish
      UPDATE account_users SET permission_profile_id = NULL
      WHERE permission_profile_id IN (SELECT id FROM permission_profiles WHERE kind = 'inbox')
    SQL
    execute <<~SQL.squish
      UPDATE inbox_members SET permission_profile_id = NULL
      WHERE permission_profile_id IN (SELECT id FROM permission_profiles WHERE kind = 'system')
    SQL
  end

  def down
    remove_index :permission_profiles, column: [:account_id, :kind]
    remove_column :permission_profiles, :kind
  end
end
