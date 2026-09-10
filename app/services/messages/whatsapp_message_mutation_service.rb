class Messages::WhatsappMessageMutationService
  def initialize(message)
    @message = message
  end

  def edit!(content)
    raise ArgumentError, 'Edited content is required' unless content.is_a?(String) && content.strip.present?

    message.with_lock { apply_edit(content.strip) }
    message
  end

  def revoke!
    message.with_lock do
      attributes = message.content_attributes.to_h.deep_dup
      return message if attributes['whatsapp_revoked']

      attributes['whatsapp_revoked'] = true
      attributes['whatsapp_revoked_at'] = Time.current.iso8601
      attributes['whatsapp_previous_content'] ||= message.content
      # A remote revoke changes how the timeline presents the message, not the
      # audit record itself. Keep content and attachments intact so the
      # original remains available after reload and for reply resolution.
      message.update!(content_attributes: attributes)
    end
    message
  end

  private

  attr_reader :message

  def apply_edit(content)
    attributes = message.content_attributes.to_h.deep_dup
    return if attributes['whatsapp_edited_content'] == content

    attributes['whatsapp_edited'] = true
    attributes['whatsapp_edited_at'] = Time.current.iso8601
    attributes['whatsapp_edited_content'] = content
    attributes['whatsapp_previous_content'] ||= message.content
    message.update!(content: content, content_attributes: attributes)
  end
end
