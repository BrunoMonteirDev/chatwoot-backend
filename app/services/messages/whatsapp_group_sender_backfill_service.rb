class Messages::WhatsappGroupSenderBackfillService
  Result = Struct.new(:scanned, :updated, :unresolved, keyword_init: true)

  PARTICIPANT_ATTRIBUTE_KEYS = %w[
    participant_jid participant_lid whatsapp_participant_jid whatsapp_participant_lid
    whatsapp_group_participant_jid whatsapp_group_participant_lid
    evolution_group_participant_jid evolution_group_participant_lid
    waha_group_participant_jid waha_group_participant_lid
  ].freeze
  CONTACT_ALIAS_KEYS = %w[
    whatsapp_jid whatsapp_lid whatsapp_phone waha_jid waha_lid waha_phone
    evolution_jid evolution_lid evolution_phone participant_jid participant_lid
  ].freeze

  def initialize(account:)
    @account = account
  end

  def perform
    @scanned = @updated = @unresolved = 0
    build_contact_indexes
    candidate_messages.find_each do |message|
      next unless group_message?(message)

      @scanned += 1
      next if valid_participant_sender?(message)

      contact = resolve_contact(message)
      if contact
        message.update_columns(sender_type: 'Contact', sender_id: contact.id, updated_at: message.updated_at) # rubocop:disable Rails/SkipsModelValidations
        @updated += 1
      else
        @unresolved += 1
      end
    end
    Result.new(scanned: @scanned, updated: @updated, unresolved: @unresolved)
  end

  private

  def candidate_messages
    @account.messages.includes(conversation: :contact).where(message_type: Message.message_types[:incoming])
  end

  def group_message?(message)
    attributes = message.content_attributes.to_h
    attributes['whatsapp_chat_type'] == 'group' || attributes['chat_type'] == 'group' ||
      attributes['whatsapp_remote_jid'].to_s.end_with?('@g.us') ||
      message.conversation.contact&.additional_attributes.to_h['whatsapp_chat_type'] == 'group'
  end

  def valid_participant_sender?(message)
    message.sender.is_a?(Contact) && message.sender.account_id == @account.id && message.sender_id != message.conversation.contact_id
  end

  def resolve_contact(message)
    aliases = aliases_from(message.content_attributes)
    return if aliases.empty?

    participant = participant_snapshots(message.conversation.contact).find do |entry|
      (aliases_from(entry) & aliases).any?
    end
    contact = contact_from_snapshot(participant)
    return contact if contact && contact.id != message.conversation.contact_id

    aliases.lazy.filter_map { |value| @contacts_by_alias[value] }.find { |candidate| candidate.id != message.conversation.contact_id }
  end

  def participant_snapshots(group_contact)
    attributes = group_contact&.additional_attributes.to_h
    Array(attributes['whatsapp_group_participants']) + Array(attributes['whatsapp_group_participant_history'])
  end

  def contact_from_snapshot(snapshot)
    return unless snapshot.respond_to?(:to_h)

    values = snapshot.to_h.stringify_keys
    contact = @contacts_by_id[values['contact_id'].to_i] if values['contact_id'].present?
    return contact if contact

    aliases_from(values).lazy.filter_map { |value| @contacts_by_alias[value] }.first
  end

  def build_contact_indexes
    @contacts_by_id = {}
    @contacts_by_alias = {}
    @account.contacts.find_each do |contact|
      @contacts_by_id[contact.id] = contact
      values = contact.additional_attributes.to_h.values_at(*CONTACT_ALIAS_KEYS)
      values << contact.phone_number
      values.compact.flat_map { |value| normalized_aliases(value) }.each { |value| @contacts_by_alias[value] ||= contact }
    end
  end

  def aliases_from(attributes)
    values = attributes.to_h.stringify_keys
    raw = PARTICIPANT_ATTRIBUTE_KEYS.filter_map { |key| values[key] }
    raw.concat(values.values_at('jid', 'lid', 'phone_jid', 'phone', 'phone_number', 'provider_id').compact)
    raw.flat_map { |value| normalized_aliases(value) }.uniq
  end

  def normalized_aliases(value)
    raw = value.to_s.strip.downcase
    return [] if raw.blank?

    digits = raw.sub(/@(lid|c\.us|s\.whatsapp\.net)\z/, '').gsub(/\D/, '')
    [raw, digits.presence].compact
  end
end
