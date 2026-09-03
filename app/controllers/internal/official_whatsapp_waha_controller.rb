class Internal::OfficialWhatsappWahaController < ActionController::API
  before_action :authenticate_bridge!

  def inbound
    result = Whatsapp::HybridWahaInboundService.new(**inbound_params).perform
    return render json: { handled: false }, status: :not_found unless result.handled

    render json: { handled: true, ignored: result.ignored, message_id: result.message&.id }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def reaction
    result = Whatsapp::HybridWahaReactionInboundService.new(**inbound_params).perform
    return render json: { handled: false }, status: :not_found unless result.handled

    render json: { handled: true, message_id: result.message&.id }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def inbound_params
    params.permit(:account_id, :inbox_id, :channel_id, :waha_session, payload: {}).to_h.symbolize_keys
  end

  def authenticate_bridge!
    head :unauthorized unless Whatsapp::HybridWahaBridgeSigner.valid?(request, path: request.path)
  end
end
