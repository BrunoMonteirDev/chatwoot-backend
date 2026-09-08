require 'base64'

class Whatsapp::HybridWahaEchoReconciliationService
  def initialize(inbox:, meta_source_id:)
    @inbox = inbox
    @meta_source_id = meta_source_id.to_s
  end

  def perform
    return unless hybrid_channel?

    token = provider_token
    return if token.blank?

    message = inbox.messages.find_by('LOWER(source_id) = ?', "waha:#{token}".downcase)
    return unless message

    external_ids = message.external_source_ids.to_h.merge('meta_cloud' => meta_source_id)
    attributes = { external_source_ids: external_ids }
    attributes[:status] = :delivered if message.sent?
    message.update!(attributes)
    message
  end

  private

  attr_reader :inbox, :meta_source_id

  def hybrid_channel?
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.hybrid_waha_enabled?
  end

  def provider_token
    return unless meta_source_id.start_with?('wamid.')

    # Coexistence WAMIDs embed the companion-device WAHA id as an ASCII token.
    # Match that provider identifier directly (WAHA ids use the 3EB0 prefix)
    # instead of correlating by message text or timestamp.
    tokens = Base64.strict_decode64(meta_source_id.delete_prefix('wamid.')).scan(/(?<![0-9a-f])(3EB0[0-9a-f]{16,60})(?![0-9a-f])/i).flatten
    tokens.one? ? tokens.first : nil
  rescue ArgumentError
    nil
  end
end
