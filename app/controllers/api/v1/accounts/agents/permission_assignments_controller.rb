class Api::V1::Accounts::Agents::PermissionAssignmentsController < Api::V1::Accounts::BaseController
  before_action :agent
  before_action :authorize_administrator!

  def show
    @account_user = Current.account.account_users.find_by!(user_id: @agent.id)
    @memberships = InboxMember.where(user_id: @agent.id, inbox_id: Current.account.inboxes.select(:id)).includes(:inbox, :permission_profile)
  end

  def update
    assignments = assignment_params[:inbox_assignments] || []
    profile_ids = assignments.map { |item| item[:permission_profile_id].to_i }
    profiles = Current.account.permission_profiles.where(id: profile_ids + [assignment_params[:permission_profile_id].to_i]).index_by(&:id)
    return render json: { error: 'Perfil de permissão inválido para esta conta.' }, status: :unprocessable_entity if (profile_ids + [assignment_params[:permission_profile_id].to_i]).any? { |id| id.positive? && !profiles.key?(id) }

    ActiveRecord::Base.transaction do
      Current.account.account_users.find_by!(user_id: @agent.id).update!(permission_profile_id: assignment_params[:permission_profile_id].presence)
      assignments.each do |item|
        membership = InboxMember.joins(:inbox).where(user_id: @agent.id, inboxes: { account_id: Current.account.id }).find_by!(inbox_id: item[:inbox_id])
        membership.update!(permission_profile_id: item[:permission_profile_id].presence)
      end
    end
    show
  end

  private

  def agent = @agent = Current.account.users.find(params[:agent_id])
  def authorize_administrator! = authorize PermissionProfile, :update?
  def assignment_params
    params.require(:permission_assignment).permit(:permission_profile_id, inbox_assignments: [:inbox_id, :permission_profile_id])
  end
end
