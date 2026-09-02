class Channels::Whatsapp::ConnectionCheckJob < ApplicationJob
  queue_as :low

  def perform(channel)
    return unless channel.provider == 'whatsapp_cloud'

    state = Whatsapp::OperationalStateService.new(channel)
    checked_at = Time.current
    Whatsapp::ChannelHealthCheckService.new(channel).perform
    state.update!(state: 'connected', checked_at: checked_at, error: nil)
  rescue Whatsapp::ChannelHealthCheckService::Error => e
    state ||= Whatsapp::OperationalStateService.new(channel)
    state.update!(state: e.permanent? ? 'disconnected' : 'error', checked_at: checked_at || Time.current, error: e.message)
    Rails.logger.warn("[WHATSAPP] Meta connection health check failed channel_id=#{channel.id} inbox_id=#{channel.inbox&.id} kind=#{e.kind}")
  end
end
