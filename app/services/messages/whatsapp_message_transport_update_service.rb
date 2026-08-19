class Messages::WhatsappMessageTransportUpdateService
  TRANSPORTS = %w[evolution meta_cloud].freeze

  def initialize(message, metadata)
    @message = message
    @metadata = metadata.stringify_keys
  end

  def perform
    raise ArgumentError, 'Invalid WhatsApp message transport metadata' unless valid?

    message.with_lock do
      attributes = message.content_attributes.to_h.deep_dup
      attributes['whatsapp_transport'] = metadata['transport']
      attributes['whatsapp_remote_jid'] = metadata['remote_jid']
      attributes['whatsapp_from_me'] = ActiveModel::Type::Boolean.new.cast(metadata['from_me'])
      message.update!(source_id: metadata['source_id'], content_attributes: attributes)
    end
    message
  end

  private

  attr_reader :message, :metadata

  def valid?
    metadata['source_id'].is_a?(String) && metadata['source_id'].match?(/\A(?:evolution|meta):.+\z/) &&
      TRANSPORTS.include?(metadata['transport']) && metadata['remote_jid'].is_a?(String) && metadata['remote_jid'].present?
  end
end
