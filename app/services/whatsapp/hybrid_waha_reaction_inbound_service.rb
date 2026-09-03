class Whatsapp::HybridWahaReactionInboundService
  Result = Struct.new(:handled, :message, keyword_init: true)

  def initialize(account_id:, inbox_id:, channel_id: nil, waha_session:, payload:)
    @account_id, @inbox_id, @channel_id, @waha_session = account_id, inbox_id, channel_id, waha_session
    @payload = payload.to_h.deep_stringify_keys
  end

  def perform
    return Result.new(handled: false) unless channel
    raise ArgumentError, 'Invalid hybrid WAHA session binding' unless channel.hybrid_waha_enabled? && channel.hybrid_waha_session == @waha_session

    message = inbox.messages.find_by(source_id: "waha:#{@payload.fetch('target_message_id')}")
    return Result.new(handled: true) unless message
    raise ArgumentError, 'Hybrid WAHA reaction target does not belong to the chat' unless message.content_attributes.to_h['whatsapp_remote_jid'] == @payload.fetch('remote_jid')

    Messages::WhatsappReactionUpdateService.new(message, {
      sender_id: @payload.fetch('sender_id'), emoji: @payload.fetch('emoji').to_s,
      transport: 'waha', origin: @payload['from_me'] ? 'mobile' : 'contact', event_id: @payload['event_id']
    }.compact).perform
    Result.new(handled: true, message: message)
  end

  private

  def channel
    scope = Channel::Whatsapp.joins(:inbox).where(account_id: @account_id, inboxes: { id: @inbox_id, account_id: @account_id })
    scope = scope.where(id: @channel_id) if @channel_id.present?
    @channel ||= scope.first
  end

  def inbox = channel.inbox
end
