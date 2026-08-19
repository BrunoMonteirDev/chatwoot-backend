class Messages::WhatsappReactionUpdateService
  TRANSPORTS = %w[evolution meta_cloud].freeze
  ORIGINS = %w[contact mobile platform].freeze

  def initialize(message, reaction)
    @message = message
    @reaction = reaction.stringify_keys
  end

  def perform
    raise ArgumentError, 'Invalid WhatsApp reaction' unless valid?

    message.with_lock do
      attributes = message.content_attributes.to_h.deep_dup
      reactions = normalized_reactions(attributes['whatsapp_reactions'])
      attributes['whatsapp_reactions'] = replace_sender_reaction(reactions)
      message.update!(content_attributes: attributes)
    end
    message
  end

  private

  attr_reader :message, :reaction

  def valid?
    reaction['sender_id'].is_a?(String) && reaction['sender_id'].length.between?(1, 200) &&
      reaction['emoji'].is_a?(String) && reaction['emoji'].length <= 64 &&
      TRANSPORTS.include?(reaction['transport']) && ORIGINS.include?(reaction['origin']) &&
      (reaction['event_id'].nil? || reaction['event_id'].is_a?(String))
  end

  def normalized_reactions(value)
    Array(value).filter_map do |item|
      next unless item.is_a?(Hash)

      item.stringify_keys.slice('sender_id', 'emoji', 'transport', 'origin', 'event_id')
    end
  end

  def replace_sender_reaction(reactions)
    matching = reactions.find { |item| item['sender_id'] == reaction['sender_id'] && item['transport'] == reaction['transport'] }
    remaining = reactions.reject { |item| item['sender_id'] == reaction['sender_id'] && item['transport'] == reaction['transport'] }
    return remaining if reaction['emoji'].empty?

    # A webhook echo of a platform reaction carries origin=mobile. Keep the
    # platform provenance already recorded while updating the event id, so the
    # operation remains idempotent without fabricating a second reaction.
    if matching && matching['emoji'] == reaction['emoji']
      remaining << matching.merge(reaction.slice('event_id').compact)
    else
      remaining << reaction.slice('sender_id', 'emoji', 'transport', 'origin', 'event_id').compact
    end
    remaining
  end
end
