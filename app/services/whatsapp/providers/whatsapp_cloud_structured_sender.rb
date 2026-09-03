class Whatsapp::Providers::WhatsappCloudStructuredSender
  # Explicit Graph errors which prove validation rejected the request before a message was accepted.
  SAFE_REJECTION_CODES = %w[100 131000 131009 131026 131047 131051 132000 132001 132005].freeze

  def initialize(channel:, message:)
    @channel, @message = channel, message
  end

  def perform
    response = HTTParty.post(endpoint, headers: headers, body: body.to_json)
    parsed = response.parsed_response
    parsed = JSON.parse(response.body) if !parsed.is_a?(Hash) && response.body.present?
    parsed = {} unless parsed.is_a?(Hash)
    wamid = parsed.dig('messages', 0, 'id')
    return Whatsapp::SendResult.new(status: :accepted, provider_message_id: wamid, http_status: response.code) if response.success? && wamid.present?

    code = parsed.dig('error', 'code').to_s
    return Whatsapp::SendResult.new(status: :deterministic_rejection, http_status: response.code, error_code: code, reason: 'graph_rejected') if response.code.between?(400, 499) && SAFE_REJECTION_CODES.include?(code)

    Whatsapp::SendResult.new(status: :ambiguous_failure, http_status: response.code, error_code: code, reason: 'unconfirmed_graph_response')
  rescue StandardError => e
    Whatsapp::SendResult.new(status: :ambiguous_failure, reason: e.class.name)
  end

  private

  attr_reader :channel, :message
  def endpoint = "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/v13.0/#{channel.provider_config['phone_number_id']}/messages"
  def headers = { 'Authorization' => "Bearer #{channel.provider_config['api_key']}", 'Content-Type' => 'application/json' }
  def body
    recipient = message.conversation.contact_inbox.source_id
    { messaging_product: 'whatsapp', recipient_type: 'individual', to: recipient, type: 'text', text: { body: message.outgoing_content } }
  end
end
