class Messages::WhatsappHistoricalMessageImportService
  TRANSPORTS = %w[meta_cloud waha].freeze
  MEDIA_TYPES = %w[image audio video document sticker].freeze

  Result = Data.define(:message, :created)

  # A quoted target can arrive in a later WAHA page. Resolve a second time
  # after a batch finishes without publishing ordinary message updates.
  def self.resolve_replies!(conversation:)
    conversation.messages.find_each do |message|
      external_id = message.content_attributes['in_reply_to_external_id']
      next if external_id.blank? || message.content_attributes['in_reply_to'].present?

      quoted = conversation.messages.find_by(source_id: external_id)
      next unless quoted

      message.update_columns(content_attributes: message.content_attributes.merge('in_reply_to' => quoted.id, 'in_reply_to_external_id' => quoted.source_id), updated_at: message.updated_at) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def initialize(account:, conversation:, payload:, attachment: nil)
    @account = account
    @conversation = conversation
    @payload = payload.stringify_keys
    @attachment = attachment
  end

  # Historical data is deliberately inserted without Message callbacks. A
  # regular Message#create publishes ActionCable events, increments unread
  # state, runs automations and can call the outbound channel. None of those
  # actions are valid for a backfill that may contain thousands of old items.
  def perform
    validate!

    Message.transaction do
      lock_source_id!
      existing = account.messages.where(inbox_id: conversation.inbox_id).find_by(source_id: source_id)
      if existing
        enrich_existing_media!(existing)
        resolve_reply!(existing)
        return Result.new(message: existing, created: false)
      end

      result = Message.insert_all!([message_attributes], returning: %w[id])
      message = Message.find(result.rows.first.first)
      attach_media!(message) if attachment.present?
      resolve_reply!(message)
      preserve_conversation_activity!
      Result.new(message: message, created: true)
    end
  end

  private

  attr_reader :account, :conversation, :payload, :attachment

  def validate!
    raise ArgumentError, 'History import requires an API or native WhatsApp inbox' unless conversation.inbox.api? || native_whatsapp_inbox?
    raise ArgumentError, 'Invalid historical WhatsApp source ID' unless source_id.match?(source_id_pattern)
    raise ArgumentError, 'Invalid historical transport' unless TRANSPORTS.include?(transport)
    raise ArgumentError, 'Invalid historical message direction' unless %w[incoming outgoing].include?(direction)
    raise ArgumentError, 'Invalid historical timestamp' unless timestamp
    raise ArgumentError, 'Invalid historical media type' if payload['media_type'].present? && !MEDIA_TYPES.include?(payload['media_type'])
  end

  def source_id
    @source_id ||= payload.fetch('source_id')
  end

  def transport
    payload.fetch('transport', (native_meta? || source_id.start_with?('meta:')) ? 'meta_cloud' : 'waha')
  end

  def source_id_pattern
    return /\Awamid\.[^\s]+\z/ if native_meta?

    transport == 'meta_cloud' ? /\Ameta:[^\s]+\z/ : /\Awaha:[^\s]+\z/
  end

  def direction
    payload.fetch('direction')
  end

  def timestamp
    value = payload['timestamp']
    return Time.zone.at(value.to_i) if value.to_s.match?(/\A\d+(?:\.\d+)?\z/) && value.to_f.positive?

    nil
  end

  def content_attributes
    attributes = {
      'whatsapp_imported_history' => true,
      'whatsapp_transport' => transport,
      "#{transport == 'meta_cloud' ? 'meta' : 'waha'}_origin" => 'history',
      "#{transport == 'meta_cloud' ? 'meta' : 'waha'}_history_thread_id" => payload.fetch('thread_id'),
      'whatsapp_from_me' => direction == 'outgoing'
    }
    attributes['whatsapp_remote_jid'] = payload['remote_jid'] if payload['remote_jid'].present?
    attributes["#{transport == 'meta_cloud' ? 'meta' : 'waha'}_history_status"] = payload['history_status'] if payload['history_status'].present?
    attributes['whatsapp_chat_type'] = 'group' if payload['chat_type'] == 'group'
    attributes['whatsapp_participant_jid'] = payload['participant_jid'] if payload['participant_jid'].present?
    attributes['whatsapp_participant_name'] = payload['participant_name'] if payload['participant_name'].present?
    attributes['historical_media_unavailable'] = true if ActiveModel::Type::Boolean.new.cast(payload['historical_media_unavailable'])
    if payload['quoted_message_id'].present?
      attributes['in_reply_to_external_id'] = native_meta? ? payload['quoted_message_id'] : "#{transport == 'meta_cloud' ? 'meta' : 'waha'}:#{payload['quoted_message_id']}"
      attributes["#{transport == 'meta_cloud' ? 'meta' : 'waha'}_quoted_message_id"] = payload['quoted_message_id']
    end
    attributes
  end

  def message_attributes
    {
      account_id: account.id,
      inbox_id: conversation.inbox_id,
      conversation_id: conversation.id,
      message_type: Message.message_types.fetch(direction),
      content_type: Message.content_types.fetch('text'),
      content: historical_content,
      processed_message_content: historical_content.truncate(150_000),
      private: false,
      status: Message.statuses.fetch(normalized_status),
      sender_type: direction == 'incoming' ? 'Contact' : nil,
      sender_id: direction == 'incoming' ? conversation.contact_id : nil,
      source_id: source_id,
      external_source_ids: { transport == 'meta_cloud' ? 'meta' : 'waha' => external_source_id },
      content_attributes: content_attributes,
      additional_attributes: { 'whatsapp_imported_history' => true },
      created_at: timestamp,
      updated_at: timestamp
    }
  end

  def normalized_status
    %w[sent delivered read failed].include?(payload['status']) ? payload['status'] : 'sent'
  end

  def attach_media!(message)
    file_type = case payload['media_type']
                when 'image' then 'image'
                when 'audio' then 'audio'
                when 'video' then 'video'
                when 'sticker' then 'image'
                else 'file'
                end
    Attachment.create!(account: account, message: message, file_type: file_type, file: attachment)
  end

  # A WAHA history retry may finally be able to fetch a media file that was
  # unavailable on the initial import. Preserve the original message/source
  # identity and attach the recovered file instead of creating a duplicate.
  def enrich_existing_media!(message)
    if attachment.present? && !message.attachments.exists?
      attach_media!(message)
      attributes = message.content_attributes.except('historical_media_unavailable')
      message.update_columns(content_attributes: attributes, updated_at: message.updated_at) # rubocop:disable Rails/SkipsModelValidations
    elsif media_unavailable? && message.attachments.none? && message.content.blank?
      message.update_columns(content: historical_content, processed_message_content: historical_content.truncate(150_000), updated_at: message.updated_at) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def media_unavailable?
    ActiveModel::Type::Boolean.new.cast(payload['historical_media_unavailable'])
  end

  def historical_content
    content = payload['content'].to_s
    return content if content.present? || !media_unavailable?

    'Mídia indisponível no histórico.'
  end

  def resolve_reply!(message)
    external_id = message.content_attributes['in_reply_to_external_id']
    return if external_id.blank?

    quoted = conversation.messages.find_by(source_id: external_id)
    return unless quoted

    attributes = message.content_attributes.merge('in_reply_to' => quoted.id, 'in_reply_to_external_id' => quoted.source_id)
    # update_columns keeps this historical operation silent too.
    message.update_columns(content_attributes: attributes, updated_at: message.updated_at)
  end

  def preserve_conversation_activity!
    # An old message must never move a conversation backwards or make it look
    # newly active. Direct SQL avoids the normal message callback side effects.
    Conversation.where(id: conversation.id)
                .where('last_activity_at IS NULL OR last_activity_at < ?', timestamp)
                .update_all(last_activity_at: timestamp, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def lock_source_id!
    return unless ActiveRecord::Base.connection.adapter_name.downcase.include?('postgres')

    quoted = ActiveRecord::Base.connection.quote("#{account.id}:#{source_id}")
    ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{quoted})::bigint)")
  end

  def native_meta?
    ActiveModel::Type::Boolean.new.cast(payload['native_meta'])
  end

  def native_whatsapp_inbox?
    channel = conversation.inbox.channel
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end

  def external_source_id
    return source_id if native_meta?

    source_id.delete_prefix(transport == 'meta_cloud' ? 'meta:' : 'waha:')
  end
end
