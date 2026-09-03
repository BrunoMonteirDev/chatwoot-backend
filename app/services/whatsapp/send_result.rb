class Whatsapp::SendResult
  attr_reader :status, :provider, :provider_message_id, :http_status, :error_code, :reason

  def initialize(status:, provider: 'meta_cloud', provider_message_id: nil, http_status: nil, error_code: nil, reason: nil)
    @status, @provider, @provider_message_id, @http_status, @error_code, @reason = status.to_sym, provider, provider_message_id, http_status, error_code, reason
  end

  def accepted? = status == :accepted
  def deterministic_rejection? = status == :deterministic_rejection
  def ambiguous_failure? = status == :ambiguous_failure
end
