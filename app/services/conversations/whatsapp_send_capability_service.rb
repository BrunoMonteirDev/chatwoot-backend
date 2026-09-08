class Conversations::WhatsappSendCapabilityService
  attr_reader :window_open

  def initialize(conversation)
    @conversation = conversation
  end

  def perform
    return not_applicable unless native_whatsapp_inbox?
    return unavailable('reauthorization_required') if channel.reauthorization_required?
    return unavailable('meta_disconnected') if channel.meta_connection_status.in?(%w[disconnected error])
    @window_open = Conversations::MessageWindowService.new(conversation).can_reply?
    return hybrid_waha if !@window_open && channel.hybrid_waha_enabled? && channel.out_of_window_strategy == 'waha'
    return outside_window unless @window_open

    connected
  end

  private

  def hybrid_waha
    state = Whatsapp::HybridWahaBridgeClient.new(channel: channel).binding(action: :status).fetch('status')
    return connected.merge(required_transport: 'waha') if state == 'connected'

    unavailable(state == 'missing' ? 'waha_missing' : 'waha_disconnected').merge(required_transport: 'waha')
  rescue Whatsapp::HybridWahaBridgeClient::Error
    unavailable('waha_disconnected').merge(required_transport: 'waha')
  end

  attr_reader :conversation

  delegate :channel, to: :inbox
  delegate :inbox, to: :conversation

  def native_whatsapp_inbox?
    channel.is_a?(Channel::Whatsapp)
  end

  def connected
    response(can_send_message: true, can_send_freeform: true, requires_template: false, template_required: false, send_block_reason: nil, connection_state: 'connected')
  end

  def outside_window
    response(can_send_message: true, can_send_freeform: false, requires_template: true, template_required: true, send_block_reason: 'outside_window_template', connection_state: 'connected')
  end

  def unavailable(reason)
    response(can_send_message: false, can_send_freeform: false, requires_template: false, template_required: false, send_block_reason: reason, connection_state: 'disconnected')
  end

  def not_applicable
    {
      applicable: false,
      can_send_message: true,
      can_send_freeform: true,
      requires_template: false,
      template_required: false,
      send_block_reason: nil,
      required_transport: nil,
      connection_state: 'not_applicable'
    }
  end

  def response(**attributes)
    { applicable: true, required_transport: 'meta_cloud' }.merge(attributes)
  end
end
