class Messages::WhatsappMessageMutationService
  REVOKED_CONTENT = 'Esta mensagem foi apagada.'.freeze

  def initialize(message)
    @message = message
  end

  def edit!(content)
    raise ArgumentError, 'Edited content is required' unless content.is_a?(String) && content.strip.present?

    message.with_lock do
      attributes = message.content_attributes.to_h.deep_dup
      return message if attributes['whatsapp_edited_content'] == content.strip

      attributes['whatsapp_edited'] = true
      attributes['whatsapp_edited_at'] = Time.current.iso8601
      attributes['whatsapp_edited_content'] = content.strip
      attributes['whatsapp_previous_content'] ||= message.content
      message.update!(content: content.strip, content_attributes: attributes)
    end
    message
  end

  def revoke!
    message.with_lock do
      attributes = message.content_attributes.to_h.deep_dup
      return message if attributes['whatsapp_revoked']

      attributes['whatsapp_revoked'] = true
      attributes['whatsapp_revoked_at'] = Time.current.iso8601
      attributes['whatsapp_previous_content'] ||= message.content
      message.update!(content: REVOKED_CONTENT, content_attributes: attributes)
    end
    message
  end

  private

  attr_reader :message
end
