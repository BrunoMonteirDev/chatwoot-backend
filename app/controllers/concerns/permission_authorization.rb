module PermissionAuthorization
  private

  def require_system_permission!(permission)
    return false if permission_service.system_allowed?(permission)

    render json: { error: 'Você não possui permissão para este recurso.' }, status: :forbidden
    true
  end

  def require_inbox_permission!(inbox, permission)
    return false if permission_service.inbox_allowed?(inbox, permission)

    render json: { error: 'Você não possui permissão para esta inbox.' }, status: :forbidden
    true
  end

  def permission_service
    @permission_service ||= Authorization::PermissionService.new(account: Current.account, user: Current.user)
  end
end
