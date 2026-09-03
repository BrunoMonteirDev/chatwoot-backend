class Whatsapp::HistoryStateService
  STATES = %w[not_eligible available pending syncing completed declined failed].freeze
  BROADCAST_PROGRESS_DELTA = 5

  def initialize(channel)
    @channel = channel
  end

  def update!(state:, progress: nil, error: nil, chunk: nil, action_available: nil)
    raise ArgumentError, 'Invalid WhatsApp history state' unless STATES.include?(state)

    state = stable_state(state)
    attributes = { meta_history_status: state, meta_history_error: safe_error(error) }
    attributes[:meta_history_started_at] = Time.current if %w[pending syncing].include?(state) && @channel.meta_history_started_at.blank?
    attributes[:meta_history_completed_at] = Time.current if %w[completed declined failed].include?(state) && @channel.meta_history_completed_at.blank?
    attributes[:meta_history_action_available] = action_available unless action_available.nil?
    attributes[:meta_history_last_chunk] = chunk if newer_chunk?(chunk)
    attributes[:meta_history_progress] = normalized_progress(progress) if progress.present? && advances_progress?(progress)

    return @channel if unchanged?(attributes)

    @channel.assign_attributes(attributes)
    @channel.save!(validate: false)
    @channel
  end

  def reset!(subscription_available:)
    @channel.assign_attributes(
      meta_history_status: subscription_available ? 'available' : 'not_eligible',
      meta_history_started_at: nil,
      meta_history_completed_at: nil,
      meta_history_progress: nil,
      meta_history_error: nil,
      meta_history_last_chunk: nil,
      meta_history_action_available: false,
      meta_history_subscription_available: subscription_available
    )
    @channel.save!(validate: false)
    @channel
  end

  private

  # A completion chunk may be dequeued before an earlier chunk. The earlier
  # chunk must still be imported, but it cannot move the lifecycle backwards.
  def stable_state(state)
    return state unless @channel.meta_history_status == 'completed' && %w[pending syncing].include?(state)

    'completed'
  end

  def normalized_progress(value)
    [[value.to_i, 0].max, 100].min
  end

  def advances_progress?(value)
    normalized_progress(value) >= @channel.meta_history_progress.to_i
  end

  def newer_chunk?(chunk)
    return false if chunk.blank?
    return true if @channel.meta_history_last_chunk.blank?

    (chunk.to_s.split(':').map(&:to_i) <=> @channel.meta_history_last_chunk.to_s.split(':').map(&:to_i)) >= 0
  end

  def safe_error(error)
    error.to_s.gsub(/[\r\n]/, ' ').truncate(500).presence
  end

  def unchanged?(attributes)
    attributes.all? { |key, value| @channel.public_send(key) == value }
  end
end
