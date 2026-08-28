class PermissionProfile < ApplicationRecord
  INBOX_PERMISSIONS = %w[conversation_view_all conversation_view_assigned conversation_view_unassigned conversation_take conversation_assign conversation_reply conversation_status_priority inbox_manage].freeze
  SYSTEM_PERMISSIONS = %w[contacts_manage labels_manage canned_responses_manage agents_manage teams_manage inboxes_manage integrations_manage audit_logs_view account_settings_manage].freeze
  AGENT_INBOX_PERMISSIONS = %w[conversation_view_all conversation_view_assigned conversation_view_unassigned conversation_take conversation_assign conversation_reply conversation_status_priority].freeze

  belongs_to :account
  has_many :account_users, dependent: :nullify
  has_many :inbox_members, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  enum :kind, { inbox: 'inbox', system: 'system' }, prefix: true
  validates :inbox_permissions, inclusion: { in: INBOX_PERMISSIONS }
  validates :system_permissions, inclusion: { in: SYSTEM_PERMISSIONS }
  validate :permissions_match_kind
  validate :only_one_default_per_account
  before_destroy :prevent_default_deletion
  after_update_commit :invalidate_access, if: :saved_change_to_inbox_permissions? || :saved_change_to_system_permissions?

  def self.default_inbox_for(account)
    account.permission_profiles.find_or_create_by!(kind: :inbox, default: true) do |profile|
      profile.name = 'Agente'
      profile.description = 'Gerencia normalmente as conversas das inboxes em que participa.'
      profile.inbox_permissions = AGENT_INBOX_PERMISSIONS
      profile.system_permissions = []
    end
  end

  def self.default_system_for(account)
    account.permission_profiles.find_or_create_by!(kind: :system, default: true) do |profile|
      profile.name = 'Acesso básico do sistema'
      profile.description = 'Acesso padrão aos recursos gerais da conta.'
      profile.inbox_permissions = []
      profile.system_permissions = %w[contacts_manage labels_manage canned_responses_manage]
    end
  end

  private

  def only_one_default_per_account
    return unless default? && account_id.present? && self.class.where(account_id: account_id, kind: kind, default: true).where.not(id: id).exists?

    errors.add(:default, 'já existe um perfil padrão nesta conta')
  end

  def prevent_default_deletion
    throw(:abort) if default?
  end

  def permissions_match_kind
    errors.add(:system_permissions, 'devem estar vazias em um perfil de inbox') if kind_inbox? && system_permissions.present?
    errors.add(:inbox_permissions, 'devem estar vazias em um perfil geral') if kind_system? && inbox_permissions.present?
  end

  def invalidate_access
    user_ids = kind_inbox? ? inbox_members.pluck(:user_id) : account_users.pluck(:user_id)
    invalidator = ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account)
    invalidator.users_visibility_changed!(user_ids: user_ids) if kind_inbox?
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end
end
