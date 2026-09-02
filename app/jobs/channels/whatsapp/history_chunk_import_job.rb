class Channels::Whatsapp::HistoryChunkImportJob < MutexApplicationJob
  queue_as :low
  retry_on LockAcquisitionError, wait: 5.seconds, attempts: 6

  def perform(channel, event)
    return unless valid_channel?(channel, event)

    key = "whatsapp:history:#{channel.account_id}:#{channel.id}:#{channel.provider_config['phone_number_id']}"
    with_lock(key, 60.seconds) { import_event(channel, event.deep_symbolize_keys) }
  end

  private

  def valid_channel?(channel, event)
    channel.is_a?(Channel::Whatsapp) && channel.history_eligible? && channel.account.active? &&
      channel.provider_config['phone_number_id'].to_s == event[:phone_number_id].to_s
  end

  def import_event(channel, event)
    state = Whatsapp::HistoryStateService.new(channel)
    return state.update!(state: event[:kind], error: event[:error], action_available: false) if %w[declined failed].include?(event[:kind])

    state.update!(state: 'syncing', progress: event[:progress], chunk: event[:chunk], action_available: false)
    Array(event[:messages]).each { |message| import_message(channel, message) }
    state.update!(state: event[:progress].to_i >= 100 ? 'completed' : 'syncing', progress: event[:progress], chunk: event[:chunk], action_available: false)
  end

  def import_message(channel, payload)
    # Realtime may have won the race and already persisted this WAMID. Reuse
    # its conversation before resolving contacts so history cannot leave an
    # empty duplicate conversation behind.
    conversation = channel.inbox.messages.find_by(source_id: payload[:source_id])&.conversation
    conversation ||= Whatsapp::HistoricalConversationResolver.new(channel: channel, remote_identifier: payload[:remote_jid]).perform
    attachment = download_attachment(channel, payload)
    Messages::WhatsappHistoricalMessageImportService.new(account: channel.account, conversation: conversation, payload: payload, attachment: attachment).perform
  rescue ArgumentError => e
    Rails.logger.warn("[WHATSAPP_HISTORY] Ignored message channel_id=#{channel.id}: #{e.message}")
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP_HISTORY] Message import failed channel_id=#{channel.id}: #{e.message}")
  end

  def download_attachment(channel, payload)
    return if payload[:media_id].blank? || payload[:media_type] == 'sticker'

    Down.download(channel.media_url(payload[:media_id]), headers: channel.api_headers)
  rescue StandardError => e
    payload[:historical_media_unavailable] = true
    Rails.logger.info("[WHATSAPP_HISTORY] Media unavailable channel_id=#{channel.id} media_type=#{payload[:media_type]} error=#{e.class}")
    nil
  end
end
