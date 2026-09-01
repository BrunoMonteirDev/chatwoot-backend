class Messages::ForwardMessageService
  class Error < StandardError; end

  def initialize(source_message:, destination_conversation:, user:, idempotency_token:)
    @source_message = source_message
    @destination_conversation = destination_conversation
    @user = user
    @idempotency_token = idempotency_token
  end

  def perform
    validate!

    Message.transaction do
      lock_idempotency_token!
      existing = destination_conversation.messages.find do |message|
        message.content_attributes.to_h['forwarding_token'] == idempotency_token
      end
      return existing if existing

      message = destination_conversation.messages.create!(
        account: destination_conversation.account,
        inbox: destination_conversation.inbox,
        message_type: :outgoing,
        content: source_message.content,
        private: false,
        sender: user,
        content_attributes: {
          'forwarding_token' => idempotency_token,
          'forwarded_from_message_id' => source_message.id,
          # Keep the user-visible WhatsApp semantic on copied messages. The
          # bridge and web UI use this same normalized key for provider-origin
          # forwarded messages.
          'whatsapp_is_forwarded' => true
        }
      )
      source_message.attachments.each { |source_attachment| copy_attachment(source_attachment, message) }
      message
    end
  end

  private

  attr_reader :source_message, :destination_conversation, :user, :idempotency_token

  def validate!
    raise Error, 'O token de idempotência é inválido.' unless idempotency_token.is_a?(String) && idempotency_token.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
    raise Error, 'Não é possível encaminhar para a própria conversa.' if source_message.conversation_id == destination_conversation.id
    raise Error, 'A conversa de destino não é uma inbox WhatsApp válida.' unless whatsapp_destination?
    raise Error, 'A mensagem não pode ser encaminhada.' unless forwardable_message?
    raise Error, 'O anexo não está disponível para encaminhamento.' if source_message.attachments.any? { |attachment| !attachment.file.attached? }
    raise Error, 'A janela de 24 horas da Meta Cloud expirou. Use um template.' if meta_destination? && !meta_window_open?
  end

  def forwardable_message?
    return false if source_message.private? || source_message.activity? || source_message.template?
    return false if source_message.content_attributes.to_h['whatsapp_revoked'] || source_message.content_attributes.to_h['deleted']

    source_message.content.present? || source_message.attachments.any?
  end

  def whatsapp_attributes
    destination_conversation.inbox.channel.additional_attributes || {}
  end

  def transports
    declared = whatsapp_attributes['whatsapp_transports'] || whatsapp_attributes[:whatsapp_transports]
    return declared if declared.is_a?(Array) && declared.any?
    return ['meta_cloud'] if whatsapp_attributes['whatsapp_provider'] == 'meta_cloud' || whatsapp_attributes[:whatsapp_provider] == 'meta_cloud'
    return ['evolution'] if whatsapp_attributes['evolution_provider'] == 'evolution' || whatsapp_attributes[:evolution_provider] == 'evolution'

    []
  end

  def whatsapp_destination?
    destination_conversation.inbox.api? && transports.any? { |transport| %w[evolution waha meta_cloud].include?(transport) }
  end

  def meta_destination?
    # The bridge routes individual hybrid conversations to Meta first. Group
    # conversations remain on WAHA/Evolution and are not subject to Meta's window.
    transports.include?('meta_cloud') && !destination_conversation.contact_inbox.source_id.start_with?('whatsapp:group:')
  end

  def meta_window_open?
    last_incoming = destination_conversation.messages.incoming.order(created_at: :desc).first
    last_incoming.present? && last_incoming.created_at >= 24.hours.ago
  end

  def copy_attachment(source_attachment, message)
    attachment = message.attachments.build(account: message.account, file_type: source_attachment.file_type, fallback_title: source_attachment.fallback_title, meta: source_attachment.meta)
    attachment.file.attach(source_attachment.file.blob)
    attachment.save!
  end

  def lock_idempotency_token!
    return unless ActiveRecord::Base.connection.adapter_name.downcase.include?('postgres')

    key = ActiveRecord::Base.connection.quote("#{destination_conversation.account_id}:forward:#{idempotency_token}")
    ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{key})::bigint)")
  end
end
