module Authorization
  class PermissionService
    def initialize(account:, user:)
      @account = account
      @user = user
      @account_user = account.account_users.find_by(user_id: user.id)
    end

    def administrator? = @account_user&.administrator?

    def system_allowed?(permission)
      administrator? || account_profile.system_permissions.include?(permission.to_s)
    end

    def inbox_allowed?(inbox, permission)
      return true if administrator?
      return false unless inbox.account_id == @account.id

      inbox_profile(inbox).inbox_permissions.include?(permission.to_s)
    end

    def can_view_conversation?(conversation)
      return true if administrator?
      profile = inbox_profile(conversation.inbox)
      return true if profile.inbox_permissions.include?('conversation_view_all')
      return true if conversation.assignee_id == @user.id && profile.inbox_permissions.include?('conversation_view_assigned')

      conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil? && profile.inbox_permissions.include?('conversation_view_unassigned')
    end

    def visible_conversations(conversations)
      return conversations if administrator?

      memberships = InboxMember.where(user_id: @user.id, inbox_id: @account.inboxes.select(:id)).includes(:permission_profile, :inbox)
      ids = memberships.each_with_object([]) do |member, result|
        profile = member.permission_profile || PermissionProfile.default_inbox_for(@account)
        scope = conversations.where(inbox_id: member.inbox_id)
        if profile.inbox_permissions.include?('conversation_view_all')
          result.concat(scope.pluck(:id))
        else
          allowed = nil
          allowed = scope.where(assignee_id: @user.id) if profile.inbox_permissions.include?('conversation_view_assigned')
          unassigned = scope.unassigned if profile.inbox_permissions.include?('conversation_view_unassigned')
          result.concat(allowed.pluck(:id)) if allowed
          result.concat(unassigned.pluck(:id)) if unassigned
        end
      end
      conversations.where(id: ids.uniq)
    end

    private

    def account_profile
      @account_user&.permission_profile || PermissionProfile.default_system_for(@account)
    end

    def inbox_profile(inbox)
      InboxMember.find_by(inbox_id: inbox.id, user_id: @user.id)&.permission_profile || PermissionProfile.default_inbox_for(@account)
    end
  end
end
