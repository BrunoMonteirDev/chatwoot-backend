class Api::V1::Accounts::Inboxes::HybridWahaBindingController < Api::V1::Accounts::BaseController
  include PermissionAuthorization
  before_action :fetch_inbox
  before_action -> { require_system_permission!('inboxes_manage') }

  def show
    return head :not_found unless whatsapp_channel

    render json: { hybrid_enabled: whatsapp_channel.hybrid_enabled?, waha_session: whatsapp_channel.hybrid_waha_session }
  end

  def create
    return head :not_found unless whatsapp_channel

    Whatsapp::HybridWahaBindingService.new(channel: whatsapp_channel, session: params.require(:waha_session)).bind!
    render json: { hybrid_enabled: whatsapp_channel.hybrid_enabled?, waha_session: whatsapp_channel.hybrid_waha_session }
  rescue Whatsapp::HybridWahaBridgeClient::Error, ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    return head :not_found unless whatsapp_channel

    Whatsapp::HybridWahaBindingService.new(channel: whatsapp_channel).unbind!
    head :no_content
  rescue Whatsapp::HybridWahaBridgeClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def whatsapp_channel
    @whatsapp_channel ||= @inbox.channel if @inbox.channel.is_a?(Channel::Whatsapp)
  end
end
