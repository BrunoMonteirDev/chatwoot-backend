class Whatsapp::SendCapabilityService
  def initialize(conversation)
    @conversation = conversation
    @channel = conversation.inbox.channel
  end

  def perform
    return unavailable_payload unless channel.is_a?(Channel::Whatsapp)
    return meta_block('reauthorization_required') if channel.reauthorization_required?
    return meta_block('meta_disconnected') unless channel.meta_connection_status == 'connected'

    decision = Whatsapp::HybridRouter.new(channel: channel, conversation: conversation, message: Message.new(content_attributes: {})).route
    return template_payload if decision.transport == :blocked
    return waha_payload(decision.reason) if decision.transport == :waha

    allowed_payload('meta_cloud')
  rescue Whatsapp::HybridRouter::Error
    # Misconfigured hybrid state must never make the browser guess a fallback.
    waha_payload('hybrid_waha_unavailable')
  end

  private

  attr_reader :conversation, :channel

  def unavailable_payload
    { applicable: false, can_send_message: true, can_send_freeform: true, requires_template: false,
      template_required: false, send_block_reason: nil, required_transport: nil, connection_state: 'not_applicable' }
  end

  def allowed_payload(transport)
    { applicable: true, can_send_message: true, can_send_freeform: true, requires_template: false,
      template_required: false, send_block_reason: nil, required_transport: transport, connection_state: 'connected' }
  end

  def meta_block(reason)
    { applicable: true, can_send_message: false, can_send_freeform: false, requires_template: false,
      template_required: false, send_block_reason: reason, required_transport: 'meta_cloud', connection_state: channel.meta_connection_status }
  end

  def template_payload
    { applicable: true, can_send_message: true, can_send_freeform: false, requires_template: true,
      template_required: true, send_block_reason: 'outside_window_template', required_transport: 'meta_cloud', connection_state: 'connected' }
  end

  def waha_payload(reason)
    state = waha_connection_state
    return allowed_payload('waha').merge(send_block_reason: nil) if state == 'connected'

    { applicable: true, can_send_message: false, can_send_freeform: false, requires_template: false,
      template_required: false, send_block_reason: state == 'missing' ? 'waha_missing' : 'waha_disconnected', required_transport: 'waha', connection_state: state,
      routing_reason: reason }
  end

  def waha_connection_state
    return 'missing' if channel.hybrid_waha_session.blank?

    result = Whatsapp::HybridWahaBridgeClient.new(channel: channel).binding(action: :status)
    result['status'].to_s == 'connected' ? 'connected' : result['status'].to_s.presence || 'disconnected'
  rescue Whatsapp::HybridWahaBridgeClient::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError
    'disconnected'
  end
end
