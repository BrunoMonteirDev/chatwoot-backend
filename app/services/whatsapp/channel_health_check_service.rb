class Whatsapp::ChannelHealthCheckService
  class Error < StandardError
    attr_reader :kind

    def initialize(message, kind:)
      super(message)
      @kind = kind
    end

    def permanent? = %i[auth resource permission].include?(kind)
  end

  BASE_URI = 'https://graph.facebook.com'.freeze

  def initialize(channel)
    @channel = channel
    @access_token = channel.provider_config['api_key']
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  # A read-only confirmation used after Meta lifecycle events. It proves the token
  # can read both configured resources and that the configured phone belongs to the WABA.
  def perform
    validate_channel!
    phone = get(@channel.provider_config['phone_number_id'], fields: 'id')
    raise Error.new('Configured phone number does not match Graph resource', kind: :resource) unless phone.with_indifferent_access[:id].to_s == @channel.provider_config['phone_number_id'].to_s

    phones = get("#{@channel.provider_config['business_account_id']}/phone_numbers", fields: 'id')
    ids = Array(phones.with_indifferent_access[:data]).filter_map { |item| item.is_a?(Hash) ? item.with_indifferent_access[:id] : nil }
    raise Error.new('Configured phone number is not available in the configured WABA', kind: :resource) unless ids.include?(@channel.provider_config['phone_number_id'])

    true
  rescue Error
    raise
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, SocketError => e
    raise Error.new('Meta health check timed out', kind: :transient), cause: e
  rescue StandardError => e
    raise Error.new('Meta health check failed', kind: :transient), cause: e
  end

  private

  def validate_channel!
    raise Error.new('WhatsApp Cloud channel is required', kind: :resource) unless @channel&.provider == 'whatsapp_cloud'
    raise Error.new('Meta access token is missing', kind: :auth) if @access_token.blank?
    raise Error.new('Meta phone number ID is missing', kind: :resource) if @channel.provider_config['phone_number_id'].blank?
    raise Error.new('Meta business account ID is missing', kind: :resource) if @channel.provider_config['business_account_id'].blank?
  end

  def get(path, fields:)
    response = HTTParty.get("#{BASE_URI}/#{@api_version}/#{path}", query: { fields: fields, access_token: @access_token })
    return parsed_body(response) if response.success?

    error = parsed_body(response).is_a?(Hash) ? parsed_body(response).with_indifferent_access[:error].to_h : {}
    raise Error.new(error['message'].presence || 'Meta Graph request failed', kind: error_kind(response.code, error['code']))
  end

  def parsed_body(response)
    body = response.parsed_response
    return body unless body.is_a?(String)

    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

  def error_kind(http_status, graph_code)
    return :auth if http_status.to_i == 401 || graph_code.to_i == 190
    return :resource if http_status.to_i == 404 || graph_code.to_i == 100
    return :permission if http_status.to_i == 403 || [10, 200].include?(graph_code.to_i)
    return :rate_limit if http_status.to_i == 429 || [4, 17, 32, 613].include?(graph_code.to_i)

    :transient
  end
end
