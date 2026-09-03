class Whatsapp::CoexistenceReonboardingService
  def initialize(channel)
    @channel = channel
  end

  def perform
    @channel.with_lock do
      @channel.reload
      return false unless @channel.coexistence? && @channel.coexistence_offboarded?

      return false unless yield

      Whatsapp::HistoryStateService.new(@channel).reset!(subscription_available: @channel.meta_history_subscription_available?)
      @channel.meta_coexistence_offboarded_at = nil
      @channel.save!(validate: false)
      Channels::Whatsapp::HistorySyncRequestJob.perform_later(@channel) if @channel.meta_history_subscription_available?
      true
    end
  end
end
