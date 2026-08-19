class Messages::WhatsappHistoricalMessageImportService
  TRANSPORT = 'meta_cloud'.freeze
  MEDIA_TYPES = %w[image audio video document].freeze

  Result = Data.define(:message, :created)

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
      existing = account.messages.find_by(source_id: source_id)
      return Result.new(message: existing, created: false) if existing

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
    raise ArgumentError, 'History import requires an API inbox' unless conversation.inbox.api?
    raise ArgumentError, 'Invalid historical Meta source ID' unless source_id.match?(/\Ameta:[^\s]+\z/)
    raise ArgumentError, 'Invalid historical message direction' unless %w[incoming outgoing].include?(direction)
    raise ArgumentError, 'Invalid historical timestamp' unless timestamp
    raise ArgumentError, 'Invalid historical media type' if payload['media_type'].present? && !MEDIA_TYPES.include?(payload['media_type'])
  end

  def source_id
    @source_id ||= payload.fetch('source_id')
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
      'whatsapp_transport' => TRANSPORT,
      'meta_origin' => 'history',
      'meta_history_thread_id' => payload.fetch('thread_id'),
      'whatsapp_from_me' => direction == 'outgoing'
    }
    attributes['whatsapp_remote_jid'] = payload['remote_jid'] if payload['remote_jid'].present?
    attributes['meta_history_status'] = payload['history_status'] if payload['history_status'].present?
    attributes['historical_media_unavailable'] = true if ActiveModel::Type::Boolean.new.cast(payload['historical_media_unavailable'])
    if payload['quoted_message_id'].present?
      attributes['in_reply_to_external_id'] = "meta:#{payload['quoted_message_id']}"
      attributes['meta_quoted_message_id'] = payload['quoted_message_id']
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
      content: payload['content'].to_s,
      processed_message_content: payload['content'].to_s.truncate(150_000),
      private: false,
      status: Message.statuses.fetch(normalized_status),
      sender_type: direction == 'incoming' ? 'Contact' : nil,
      sender_id: direction == 'incoming' ? conversation.contact_id : nil,
      source_id: source_id,
      external_source_ids: { 'meta' => source_id.delete_prefix('meta:') },
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
                else 'file'
                end
    Attachment.create!(account: account, message: message, file_type: file_type, file: attachment)
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
end
