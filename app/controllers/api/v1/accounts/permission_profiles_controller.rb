class Api::V1::Accounts::PermissionProfilesController < Api::V1::Accounts::BaseController
  before_action :profile, only: [:show, :update, :destroy]

  def index
    authorize PermissionProfile
    PermissionProfile.default_inbox_for(Current.account)
    PermissionProfile.default_system_for(Current.account)
    @permission_profiles = Current.account.permission_profiles.order(:name)
  end

  def show
    authorize @permission_profile
  end

  def create
    authorize PermissionProfile
    @permission_profile = Current.account.permission_profiles.create!(profile_params)
    render :show, status: :created
  end

  def update
    authorize @permission_profile
    @permission_profile.update!(profile_params)
    render :show
  end

  def destroy
    authorize @permission_profile
    return render json: { error: 'O perfil padrão não pode ser excluído.' }, status: :unprocessable_entity if @permission_profile.default?

    @permission_profile.destroy!
    head :no_content
  end

  private

  def profile = @permission_profile = Current.account.permission_profiles.find(params[:id])
  def profile_params = params.require(:permission_profile).permit(:name, :description, :kind, inbox_permissions: [], system_permissions: [])
end
