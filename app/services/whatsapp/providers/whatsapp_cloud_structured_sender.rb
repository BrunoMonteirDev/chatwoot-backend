class Whatsapp::Providers::WhatsappCloudStructuredSender < Whatsapp::Providers::WhatsappCloudService
  # Explicit Graph errors which prove validation rejected the request before a message was accepted.
  SAFE_REJECTION_CODES = %w[100 131000 131009 131026 131047 131051 132000 132001 132005].freeze

  def initialize(channel:, message:)
    @channel, @message = channel, message
    super(whatsapp_channel: channel)
  end

  def perform
    send_message(message.conversation.contact_inbox.source_id, message)
  rescue StandardError => e
    Whatsapp::SendResult.new(status: :ambiguous_failure, reason: e.class.name)
  end

  def process_response(response, _message)
    parsed = response.parsed_response
    parsed = JSON.parse(response.body) if !parsed.is_a?(Hash) && response.body.present?
    parsed = {} unless parsed.is_a?(Hash)
    wamid = parsed.dig('messages', 0, 'id')
    return Whatsapp::SendResult.new(status: :accepted, provider_message_id: wamid, http_status: response.code) if response.success? && wamid.present?

    code = parsed.dig('error', 'code').to_s
    return Whatsapp::SendResult.new(status: :deterministic_rejection, http_status: response.code, error_code: code, reason: 'graph_rejected') if response.code.between?(400, 499) && SAFE_REJECTION_CODES.include?(code)

    Whatsapp::SendResult.new(status: :ambiguous_failure, http_status: response.code, error_code: code, reason: 'unconfirmed_graph_response')
  end

  private

  attr_reader :channel, :message
end
