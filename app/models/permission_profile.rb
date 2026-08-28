class PermissionProfile < ApplicationRecord
  INBOX_PERMISSIONS = %w[conversation_view_all conversation_view_assigned conversation_view_unassigned conversation_take conversation_assign conversation_reply conversation_status_priority inbox_manage].freeze
  SYSTEM_PERMISSIONS = %w[contacts_manage labels_manage canned_responses_manage agents_manage teams_manage inboxes_manage integrations_manage audit_logs_view account_settings_manage].freeze
  AGENT_INBOX_PERMISSIONS = %w[conversation_view_all conversation_view_assigned conversation_view_unassigned conversation_take conversation_assign conversation_reply conversation_status_priority].freeze

  belongs_to :account
  has_many :account_users, dependent: :nullify
  has_many :inbox_members, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :inbox_permissions, inclusion: { in: INBOX_PERMISSIONS }
  validates :system_permissions, inclusion: { in: SYSTEM_PERMISSIONS }
  validate :only_one_default_per_account
  before_destroy :prevent_default_deletion

  def self.default_for(account)
    account.permission_profiles.find_or_create_by!(default: true) do |profile|
      profile.name = 'Agente'
      profile.description = 'Gerencia normalmente as conversas das inboxes em que participa.'
      profile.inbox_permissions = AGENT_INBOX_PERMISSIONS
      profile.system_permissions = %w[contacts_manage labels_manage canned_responses_manage]
    end
  end

  private

  def only_one_default_per_account
    return unless default? && account_id.present? && self.class.where(account_id: account_id, default: true).where.not(id: id).exists?

    errors.add(:default, 'já existe um perfil padrão nesta conta')
  end

  def prevent_default_deletion
    throw(:abort) if default?
  end
end
