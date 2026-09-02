class Whatsapp::HistoricalConversationResolver
  def initialize(channel:, remote_identifier:)
    @channel = channel
    @remote_identifier = remote_identifier.to_s.gsub(/\D/, '')
  end

  def perform
    raise ArgumentError, 'Invalid historical WhatsApp contact' unless @remote_identifier.match?(/\A\d{1,15}\z/)

    contact_inbox = ContactInboxSourceIdResolver.new(
      inbox: inbox, source_ids: [normalized_identifier, @remote_identifier].compact.uniq,
      contact_attributes: { name: "+#{@remote_identifier}", phone_number: "+#{@remote_identifier}" }
    ).perform
    conversation = contact_inbox.contact.conversations.where(inbox_id: inbox.id).where.not(status: :resolved).last
    conversation ||= Conversation.create!(account_id: inbox.account_id, inbox_id: inbox.id, contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id)
    conversation
  end

  private

  def inbox
    @inbox ||= @channel.inbox
  end

  def normalized_identifier
    Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(@remote_identifier, :cloud)
  rescue StandardError
    nil
  end
end
