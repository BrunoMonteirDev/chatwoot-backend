class Whatsapp::HybridRouter
  Decision = Struct.new(:transport, :reason, :fallback_used, keyword_init: true)
  class Error < StandardError; end

  def initialize(channel:, conversation:, message:)
    @channel, @conversation, @message = channel, conversation, message
  end

  def route
    return Decision.new(transport: :meta_cloud, reason: 'hybrid_disabled', fallback_used: false) unless channel.hybrid_waha_enabled?
    return waha('group_waha') if group?
    return Decision.new(transport: :meta_cloud, reason: 'meta_primary', fallback_used: false) if conversation.can_reply?
    return waha('outside_window_waha') if channel.out_of_window_strategy == 'waha'

    Decision.new(transport: :blocked, reason: 'outside_window_template', fallback_used: false)
  end

  def dispatch
    decision = route
    case decision.transport
    when :meta_cloud then send_meta(decision) { yield decision }
    when :waha then send_waha(decision)
    else raise Error, I18n.t('errors.whatsapp.message_outside_messaging_window')
    end
  end

  private

  attr_reader :channel, :conversation, :message

  def group?
    conversation.contact_inbox&.source_id.to_s.start_with?('whatsapp:group:') || message.content_attributes.to_h['whatsapp_remote_jid'].to_s.end_with?('@g.us')
  end

  def waha(reason)
    validate_binding!
    raise Error, 'WAHA session is not configured for this inbox' if channel.hybrid_waha_session.blank?

    Decision.new(transport: :waha, reason: reason, fallback_used: false)
  end

  def validate_binding!
    raise Error, 'Hybrid channel does not belong to this inbox' unless channel.inbox.id == conversation.inbox_id && channel.account_id == conversation.account_id
    raise Error, 'Hybrid WAHA is not enabled for this inbox' unless channel.hybrid_waha_enabled?
  end

  def send_waha(decision)
    remote_jid = message.content_attributes.to_h['whatsapp_remote_jid'].presence || conversation.contact_inbox&.source_id
    remote_jid = remote_jid.delete_prefix('whatsapp:group:') if remote_jid.to_s.start_with?('whatsapp:group:')
    attachment = message.attachments.first
    operation = attachment&.file_type || :text
    result = Whatsapp::HybridWahaBridgeClient.new(channel: channel).dispatch(
      operation: operation, conversation: conversation, message: message,
      payload: { remote_jid: remote_jid, content: message.content, reply_to: reply_target_provider_key,
                 attachment: attachment && { url: attachment.file_url, file_name: attachment.file.filename.to_s, content_type: attachment.file.content_type } }
    )
    Messages::WhatsappMessageTransportUpdateService.new(message, {
      source_id: result.fetch('source_id'), transport: 'waha', remote_jid: remote_jid, from_me: true, provider_message_key: result['provider_message_key']
    }).perform
    log(decision)
    result
  end

  def reply_target_provider_key
    target_id = message.content_attributes.to_h['in_reply_to']
    return if target_id.blank?

    target = conversation.messages.find_by(id: target_id)
    raise Error, 'WAHA reply target was not found in this conversation' unless target

    target.content_attributes.to_h['whatsapp_provider_message_key'].presence || raise(Error, 'WAHA reply target provider key is required')
  end

  def send_meta(decision)
    result = Whatsapp::Providers::WhatsappCloudStructuredSender.new(channel: channel, message: message).perform
    if result.accepted?
      message.update!(source_id: result.provider_message_id)
      log(decision)
      return result
    end
    raise Error, 'Meta rejected the message and fallback is blocked' if result.deterministic_rejection? && channel.meta_failure_strategy == 'block'
    return send_waha(Decision.new(transport: :waha, reason: 'meta_failure_waha', fallback_used: true)) if result.deterministic_rejection? && channel.meta_failure_strategy == 'waha'

    raise Error, 'Meta delivery result is uncertain; WAHA fallback was not attempted'
  end

  def log(decision)
    Rails.logger.info("[HYBRID_WAHA] account_id=#{channel.account_id} inbox_id=#{conversation.inbox_id} conversation_id=#{conversation.id} operation=send transport=#{decision.transport} reason=#{decision.reason} fallback_used=#{decision.fallback_used}")
  end
end
