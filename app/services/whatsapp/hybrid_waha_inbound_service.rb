class Whatsapp::HybridWahaInboundService
  Result = Struct.new(:handled, :ignored, :message, keyword_init: true)

  def initialize(account_id:, inbox_id:, channel_id: nil, waha_session:, payload:)
    @account_id, @inbox_id, @channel_id, @waha_session, @payload = account_id, inbox_id, channel_id, waha_session, payload.to_h.deep_stringify_keys
  end

  def perform
    return Result.new(handled: false, ignored: false) unless channel
    raise ArgumentError, 'Invalid hybrid WAHA session binding' unless channel.hybrid_waha_enabled? && channel.hybrid_waha_session == @waha_session
    return Result.new(handled: true, ignored: true) unless group?

    existing = Message.find_by(account_id: channel.account_id, source_id: source_id)
    return Result.new(handled: true, ignored: false, message: existing) if existing

    ActiveRecord::Base.transaction do
      contact_inbox = ContactInboxSourceIdResolver.new(
        inbox: inbox, source_ids: [group_source_id], contact_attributes: { name: @payload['group_name'].presence || remote_jid }
      ).perform
      conversation = contact_inbox.contact.conversations.where(inbox_id: inbox.id).where.not(status: :resolved).last ||
                     Conversation.create!(account: inbox.account, inbox: inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox)
      message = conversation.messages.create!(
        account: inbox.account, inbox: inbox, sender: @payload['from_me'] ? nil : contact_inbox.contact,
        message_type: @payload['from_me'] ? :outgoing : :incoming, status: @payload['from_me'] ? :delivered : :sent,
        content: @payload['content'].to_s, source_id: source_id,
        content_attributes: transport_attributes
      )
      Result.new(handled: true, ignored: false, message: message)
    end
  rescue ActiveRecord::RecordNotUnique
    Result.new(handled: true, ignored: false, message: Message.find_by!(account_id: @account_id, source_id: source_id))
  end

  private

  def channel
    scope = Channel::Whatsapp.joins(:inbox).where(account_id: @account_id, inboxes: { id: @inbox_id, account_id: @account_id })
    scope = scope.where(id: @channel_id) if @channel_id.present?
    @channel ||= scope.first
  end
  def inbox = channel.inbox
  def remote_jid = @payload.fetch('remote_jid').to_s
  def group? = remote_jid.end_with?('@g.us')
  def source_id = "waha:#{@payload.fetch('external_id')}"
  def group_source_id = "whatsapp:group:#{remote_jid}"
  def transport_attributes
    {
      'whatsapp_transport' => 'waha', 'whatsapp_remote_jid' => remote_jid,
      'whatsapp_provider_message_key' => @payload['provider_message_key'],
      'whatsapp_participant_jid' => @payload['participant_jid'],
      'whatsapp_participant_name' => @payload['participant_name'],
      'whatsapp_chat_type' => 'group', 'in_reply_to_external_id' => @payload['quoted_message_id'].presence && "waha:#{@payload['quoted_message_id']}"
    }.compact
  end
end
