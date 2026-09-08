require 'openssl'

class Whatsapp::HybridWahaBridgeSigner
  TTL = 300.seconds

  def self.headers(method:, path:, body:, timestamp: Time.now.to_i, request_id: SecureRandom.uuid)
    secret = ENV.fetch('HYBRID_WAHA_BRIDGE_SECRET')
    canonical = [method.upcase, path, timestamp, request_id, body].join("\n")
    {
      'X-Hybrid-Waha-Timestamp' => timestamp.to_s,
      'X-Hybrid-Waha-Request-Id' => request_id,
      'X-Hybrid-Waha-Signature' => OpenSSL::HMAC.hexdigest('SHA256', secret, canonical)
    }
  end

  def self.valid?(request, path:)
    secret = ENV.fetch('HYBRID_WAHA_BRIDGE_SECRET', '')
    timestamp = request.headers['X-Hybrid-Waha-Timestamp'].to_i
    request_id = request.headers['X-Hybrid-Waha-Request-Id'].to_s
    return false if secret.blank? || request_id.blank? || (Time.now.to_i - timestamp).abs > TTL

    canonical = [request.request_method, path, timestamp, request_id, request.raw_post].join("\n")
    expected = OpenSSL::HMAC.hexdigest('SHA256', secret, canonical)
    supplied = request.headers['X-Hybrid-Waha-Signature'].to_s
    supplied.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
  end
end
