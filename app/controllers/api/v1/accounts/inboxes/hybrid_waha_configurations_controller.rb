class Api::V1::Accounts::Inboxes::HybridWahaConfigurationsController < Api::V1::Accounts::BaseController
  include PermissionAuthorization

  before_action :fetch_inbox
  before_action -> { require_system_permission!('inboxes_manage') }

  def show
    return head :not_found unless whatsapp_channel

    render json: configuration_payload
  end

  def update
    return head :not_found unless whatsapp_channel

    Whatsapp::HybridWahaConfigurationService.new(channel: whatsapp_channel, attributes: configuration_params).update!
    render json: configuration_payload
  rescue Whatsapp::HybridWahaConfigurationService::Error => e
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

  def configuration_params
    params.permit(:hybrid_enabled, :out_of_window_strategy, :meta_failure_strategy)
  end

  def configuration_payload
    {
      hybrid_enabled: whatsapp_channel.hybrid_enabled?,
      waha_session: whatsapp_channel.hybrid_waha_session,
      out_of_window_strategy: whatsapp_channel.out_of_window_strategy,
      meta_failure_strategy: whatsapp_channel.meta_failure_strategy
    }
  end
end
