class AutomationRulePolicy < ApplicationPolicy
  def index?
    can_manage_automations?
  end

  def create?
    can_manage_automations?
  end

  def show?
    can_manage_automations?
  end

  def update?
    can_manage_automations?
  end

  def clone?
    can_manage_automations?
  end

  def destroy?
    can_manage_automations?
  end

  private

  def can_manage_automations?
    return true if @account_user&.administrator?

    (@account_user&.permission_profile || PermissionProfile.default_system_for(@account))
      .system_permissions.include?('account_settings_manage')
  end
end
