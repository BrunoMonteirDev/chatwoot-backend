class Whatsapp::ReactionService
  class Error < StandardError; end

  def initialize(message:, emoji:, user:)
    @message = message
    @emoji = emoji.to_s
    @user = user
  end

  def perform
    return perform_waha if waha_message?

    validate!
    channel.provider_service.send_reaction(contact_source_id, message.source_id, emoji)
    Messages::WhatsappReactionUpdateService.new(message, sender_reaction).perform
  rescue Whatsapp::Providers::WhatsappCloudService::ReactionError => e
    raise Error, e.message
  end

  private

  attr_reader :message, :emoji, :user

  def channel
    message.conversation.inbox.channel
  end

  def contact_source_id
    message.conversation.contact_inbox&.source_id.presence || raise(Error, 'WhatsApp contact is required')
  end

  def validate!
    raise Error, 'WhatsApp Cloud message is required' unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
    raise Error, 'A reaction requires a WhatsApp message id' unless message.source_id.to_s.start_with?('wamid.')
    raise Error, 'WhatsApp Cloud reactions are not available for groups' if message.content_attributes.to_h['whatsapp_remote_jid'].to_s.end_with?('@g.us')
    raise Error, 'Invalid reaction emoji' unless emoji.length <= 64
  end

  def waha_message?
    message.content_attributes.to_h['whatsapp_transport'] == 'waha'
  end

  def perform_waha
    key = message.content_attributes.to_h['whatsapp_provider_message_key'].presence || raise(Error, 'WAHA provider message key is required')
    remote_jid = message.content_attributes.to_h['whatsapp_remote_jid'].presence || raise(Error, 'WAHA remote JID is required')
    raise Error, 'Hybrid WAHA is not enabled for this inbox' unless channel.respond_to?(:hybrid_waha_enabled?) && channel.hybrid_waha_enabled?

    Whatsapp::HybridWahaBridgeClient.new(channel: channel).dispatch(
      operation: :reaction, conversation: message.conversation, message: message,
      payload: { remote_jid: remote_jid, target_message_id: key, emoji: emoji }
    )
    Messages::WhatsappReactionUpdateService.new(message, { sender_id: 'self', emoji: emoji, transport: 'waha', origin: 'platform' }).perform
  rescue Whatsapp::HybridWahaBridgeClient::Error => e
    raise Error, e.message
  end

  def sender_reaction
    # `self` is the stable UI identity for the current WhatsApp business sender.
    # It also lets the later Meta echo reconcile the optimistic reaction instead
    # of manufacturing a second entry tied to an application user id.
    { sender_id: 'self', emoji: emoji, transport: 'meta_cloud', origin: 'platform' }
  end
end
