class Whatsapp::HybridWahaBindingService
  class CompensationError < StandardError; end
  def initialize(channel:, session: nil)
    @channel, @session = channel, session
  end

  def bind!
    raise ArgumentError, 'Only official WhatsApp channels can bind WAHA' unless channel.is_a?(Channel::Whatsapp)
    raise ArgumentError, 'WAHA session is required' if session.blank?

    details = client.session(action: :status, session: session).fetch('session')
    raise ArgumentError, 'A sessão WAHA ainda não está conectada.' unless details['connectionStatus'] == 'connected'
    raise ArgumentError, 'A sessão WAHA conectada pertence a outro número. Conecte o mesmo WhatsApp utilizado nesta Inbox oficial.' unless same_phone?(details.dig('me', 'id'))

    reserved = true if client.binding(action: :bind, session: session)
    channel.update!(hybrid_waha_session: session, hybrid_enabled: true)
    channel
  rescue StandardError => e
    # If Rails cannot persist after a bridge reservation, compensate. The
    # bridge unbind operation is idempotent and never stops the WAHA session.
    return raise e unless reserved

    begin
      client.binding(action: :unbind, session: session)
    rescue StandardError => compensation_error
      Rails.logger.error("[HYBRID_WAHA] binding compensation failed channel_id=#{channel.id}: #{compensation_error.class}")
      raise CompensationError, 'Hybrid WAHA binding compensation failed'
    end
    raise e
  end

  def unbind!
    return channel unless channel.hybrid_waha_session.present?

    client.binding(action: :unbind)
    # Unbinding releases only the complementary WAHA transport. It must never
    # disconnect Meta or silently change the administrator's hybrid setting.
    channel.update!(hybrid_waha_session: nil)
    channel
  end

  private

  attr_reader :channel, :session

  def client
    @client ||= Whatsapp::HybridWahaBridgeClient.new(channel: channel)
  end

  def same_phone?(jid)
    normalize(jid) == normalize(channel.phone_number)
  end

  def normalize(value)
    value.to_s.sub(/@(c\.us|s\.whatsapp\.net)\z/i, '').gsub(/\D/, '')
  end
end
