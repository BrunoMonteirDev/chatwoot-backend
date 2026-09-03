class Api::V1::Accounts::Inboxes::HybridWahaSessionsController < Api::V1::Accounts::BaseController
  include PermissionAuthorization
  before_action :fetch_inbox
  before_action -> { require_system_permission!('inboxes_manage') }

  def index
    render json: { sessions: service.list! }
  rescue Whatsapp::HybridWahaBridgeClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    render json: { session: service.create! }, status: :created
  rescue Whatsapp::HybridWahaBridgeClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def show
    render json: service.action!(:status, params[:id])
  rescue Whatsapp::HybridWahaBridgeClient::Error, ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    operation = params.require(:operation)
    result = service.action!(operation, params[:id])
    if operation == 'status' && result['session']&.dig('connectionStatus') == 'connected' && whatsapp_channel.hybrid_waha_session != params[:id]
      Whatsapp::HybridWahaSessionService.new(channel: whatsapp_channel).bind_connected!(params[:id])
    end
    render json: result
  rescue Whatsapp::HybridWahaBridgeClient::Error, Whatsapp::HybridWahaSessionService::Error, ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    Whatsapp::HybridWahaBindingService.new(channel: whatsapp_channel).unbind! if whatsapp_channel.hybrid_waha_session == params[:id]
    service.action!(:delete, params[:id])
    head :no_content
  rescue Whatsapp::HybridWahaBridgeClient::Error, ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
    return head(:not_found) unless whatsapp_channel
  end

  def whatsapp_channel
    @whatsapp_channel ||= @inbox.channel if @inbox.channel.is_a?(Channel::Whatsapp)
  end

  def service
    @service ||= Whatsapp::HybridWahaSessionService.new(channel: whatsapp_channel)
  end
end
