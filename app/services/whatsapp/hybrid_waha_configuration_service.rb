class Whatsapp::HybridWahaConfigurationService
  class Error < StandardError; end

  OUT_OF_WINDOW_STRATEGIES = %w[template waha].freeze
  META_FAILURE_STRATEGIES = %w[block waha].freeze

  def initialize(channel:, attributes:)
    @channel = channel
    @attributes = attributes.to_h.symbolize_keys
  end

  def update!
    raise Error, 'Only official WhatsApp channels support hybrid configuration' unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'

    hybrid_enabled = boolean_value(:hybrid_enabled, channel.hybrid_enabled?)
    out_of_window_strategy = enum_value(:out_of_window_strategy, OUT_OF_WINDOW_STRATEGIES, channel.out_of_window_strategy)
    meta_failure_strategy = enum_value(:meta_failure_strategy, META_FAILURE_STRATEGIES, channel.meta_failure_strategy)

    channel.assign_attributes(
      hybrid_enabled: hybrid_enabled,
      out_of_window_strategy: out_of_window_strategy,
      meta_failure_strategy: meta_failure_strategy
    )
    # These fields do not alter Meta credentials. Avoid a remote credential
    # check turning a local configuration change into an unrelated failure.
    channel.save!(validate: false)
    channel
  end

  private

  attr_reader :channel, :attributes

  def boolean_value(key, default)
    return default unless attributes.key?(key)

    value = attributes[key]
    return value if value == true || value == false
    return true if value == 'true'
    return false if value == 'false'

    raise Error, "#{key} must be a boolean"
  end

  def enum_value(key, allowed, default)
    return default unless attributes.key?(key)

    value = attributes[key].to_s
    raise Error, "#{key} is invalid" unless allowed.include?(value)

    value
  end
end
