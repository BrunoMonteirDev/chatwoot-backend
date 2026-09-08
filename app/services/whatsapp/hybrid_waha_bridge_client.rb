require 'net/http'
require 'openssl'

class Whatsapp::HybridWahaBridgeClient
  class Error < StandardError; end

  OPERATIONS = %w[text image audio video document reaction reply].freeze

  def initialize(channel:)
    @channel = channel
  end

  def dispatch(operation:, conversation:, message:, payload: {})
    raise Error, 'Hybrid WAHA is not enabled for this channel' unless channel.hybrid_waha_enabled?
    raise Error, 'Unsupported hybrid WAHA operation' unless OPERATIONS.include?(operation.to_s)
    raise Error, 'Conversation does not belong to this official inbox' unless conversation.inbox_id == inbox.id

    body = {
      account_id: channel.account_id, inbox_id: inbox.id, channel_id: channel.id,
      waha_session: channel.hybrid_waha_session, operation: operation.to_s,
      conversation_id: conversation.id, message_id: message.id, payload: payload
    }.to_json
    uri = URI.join(bridge_url, '/internal/official-whatsapp/waha/operations')
    request = Net::HTTP::Post.new(uri, { 'Content-Type' => 'application/json' }.merge(Whatsapp::HybridWahaBridgeSigner.headers(method: 'POST', path: uri.path, body: body)))
    request.body = body
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 20) { |http| http.request(request) }
    raise Error, "Hybrid WAHA bridge rejected operation (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  private

  attr_reader :channel

  def inbox
    @inbox ||= channel.inbox
  end

  def bridge_url
    ENV.fetch('HYBRID_WAHA_BRIDGE_URL')
  rescue KeyError
    raise Error, 'HYBRID_WAHA_BRIDGE_URL is not configured'
  end

  def binding(action:, session: nil)
    body = { account_id: channel.account_id, inbox_id: inbox.id, channel_id: channel.id, waha_session: session || channel.hybrid_waha_session }.to_json
    uri = URI.join(bridge_url, "/internal/official-whatsapp/waha/binding/#{action}")
    request = Net::HTTP::Post.new(uri, { 'Content-Type' => 'application/json' }.merge(Whatsapp::HybridWahaBridgeSigner.headers(method: 'POST', path: uri.path, body: body)))
    request.body = body
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 20) { |http| http.request(request) }
    raise Error, "Hybrid WAHA bridge rejected binding (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def session(action:, session: nil)
    body = { account_id: channel.account_id, inbox_id: inbox.id, channel_id: channel.id, waha_session: session }.compact.to_json
    uri = URI.join(bridge_url, "/internal/official-whatsapp/waha/session/#{action}")
    request = Net::HTTP::Post.new(uri, { 'Content-Type' => 'application/json' }.merge(Whatsapp::HybridWahaBridgeSigner.headers(method: 'POST', path: uri.path, body: body)))
    request.body = body
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 20) { |http| http.request(request) }
    return {} if response.is_a?(Net::HTTPNoContent)
    raise Error, "Hybrid WAHA bridge rejected session (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  public :binding, :session
end
