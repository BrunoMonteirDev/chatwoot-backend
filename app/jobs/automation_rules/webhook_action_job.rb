require 'net/http'
require 'uri'

class AutomationRules::WebhookActionJob < ApplicationJob
  queue_as :medium

  METHODS = %w[GET POST PUT PATCH DELETE].freeze

  def perform(config, event_payload)
    config = config.with_indifferent_access
    uri = URI.parse(config.fetch(:url))
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    method = config.fetch(:method, 'POST').to_s.upcase
    return unless METHODS.include?(method)

    request = Net::HTTP.const_get(method.capitalize).new(uri)
    headers = config[:headers]
    headers = JSON.parse(headers) if headers.is_a?(String) && headers.present?
    headers = {} unless headers.is_a?(Hash)
    headers.each { |key, value| request[key.to_s] = value.to_s }
    body = config[:body].presence
    request.body = body || event_payload.to_json unless method == 'GET'
    request['Content-Type'] ||= 'application/json' unless method == 'GET'

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
  rescue URI::InvalidURIError, KeyError, JSON::ParserError => e
    Rails.logger.warn("[AutomationRule] Invalid webhook configuration: #{e.message}")
  end
end
