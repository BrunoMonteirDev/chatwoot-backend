class Whatsapp::OperationalStateService
  STATES = %w[connected connecting disconnected error].freeze

  def initialize(channel)
    @channel = channel
  end

  def update!(state:, event: nil, checked_at: nil, error: nil, coexistence_offboarded: false)
    raise ArgumentError, 'Invalid WhatsApp operational state' unless STATES.include?(state)

    now = Time.current
    attributes = {
      meta_connection_status: state,
      meta_connection_last_error: error&.to_s&.truncate(500)
    }
    attributes[:meta_connection_last_checked_at] = checked_at if checked_at.present?
    attributes[:meta_connection_last_changed_at] = now if @channel.meta_connection_status != state || @channel.meta_connection_last_changed_at.blank?
    if event.present? && (@channel.meta_account_update_event != event || @channel.meta_account_update_at.blank?)
      attributes[:meta_account_update_event] = event
      attributes[:meta_account_update_at] = now
    end
    if coexistence_offboarded && @channel.meta_coexistence_offboarded_at.blank?
      attributes[:meta_coexistence_offboarded_at] = now
    end

    return @channel if attributes.empty? || unchanged?(attributes)

    # Operational lifecycle updates must remain available precisely when remote
    # credential validation is failing. Saving without that validation still
    # runs callbacks and touches the inbox, which emits inbox.updated.
    @channel.assign_attributes(attributes)
    @channel.save!(validate: false)
    @channel
  end

  private

  def unchanged?(attributes)
    attributes.all? { |key, value| @channel.public_send(key) == value }
  end
end
