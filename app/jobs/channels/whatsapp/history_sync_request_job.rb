class Channels::Whatsapp::HistorySyncRequestJob < ApplicationJob
  queue_as :low

  # This job is intentionally one-shot. A declined or expired request is a
  # normal product outcome and must never create an automatic retry loop.
  def perform(channel)
    return unless channel.is_a?(Channel::Whatsapp) && channel.history_eligible?
    return unless channel.meta_history_subscription_available?
    return unless channel.meta_history_status == 'available'

    Whatsapp::HistoryStateService.new(channel).update!(state: 'pending', action_available: false)
    Whatsapp::FacebookApiClient.new(channel.provider_config['api_key']).request_smb_app_data(
      channel.provider_config['phone_number_id'], sync_type: 'history'
    )
  rescue StandardError => e
    Whatsapp::HistoryStateService.new(channel.reload).update!(state: 'failed', error: e.message, action_available: false)
    Rails.logger.warn("[WHATSAPP_HISTORY] Sync request failed channel_id=#{channel.id} inbox_id=#{channel.inbox&.id}: #{e.message}")
  end
end
