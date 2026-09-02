class Whatsapp::HistoryWebhookParser
  DECLINED_ERROR_CODES = %w[2593109].freeze
  MAX_MESSAGES_PER_JOB = 20

  def initialize(params)
    @params = params.deep_symbolize_keys
  end

  def events
    changes.filter_map { |change| parse_change(change) }.flatten
  end

  private

  attr_reader :params

  def changes
    params.fetch(:entry, []).flat_map { |entry| entry.fetch(:changes, []) }
  end

  def parse_change(change)
    return unless change[:field] == 'history'

    value = change[:value].to_h
    metadata = value[:metadata].to_h
    return if metadata[:phone_number_id].blank?

    if value[:errors].present?
      return [{ kind: declined?(value[:errors]) ? 'declined' : 'failed', phone_number_id: metadata[:phone_number_id].to_s,
                error: safe_error(value[:errors]) }]
    end

    value.fetch(:history, []).flat_map do |chunk|
      chunk_metadata = chunk[:metadata].to_h
      messages = chunk.fetch(:threads, []).flat_map { |thread| normalize_thread(thread) }
      base = {
        kind: messages.empty? ? 'progress' : 'chunk', phone_number_id: metadata[:phone_number_id].to_s,
        progress: chunk_metadata[:progress], chunk: [chunk_metadata[:phase], chunk_metadata[:chunk_order]].compact.join(':'),
        messages: messages
      }
      messages.each_slice(MAX_MESSAGES_PER_JOB).map { |slice| base.merge(messages: slice, kind: 'chunk') }.presence || [base]
    end
  end

  def normalize_thread(thread)
    thread_id = thread[:id].to_s
    return [] if thread_id.blank?

    thread.fetch(:messages, []).filter_map do |message|
      wamid = message[:id].to_s
      next unless wamid.start_with?('wamid.')

      direction = message[:from].to_s == business_number ? 'outgoing' : 'incoming'
      {
        source_id: wamid, transport: 'meta_cloud', native_meta: true, direction: direction,
        timestamp: message[:timestamp], content: message.dig(:text, :body) || message.dig(:image, :caption) || message.dig(:video, :caption),
        thread_id: thread_id, remote_jid: direction == 'incoming' ? message[:from].to_s : message[:to].to_s,
        quoted_message_id: message.dig(:context, :id), history_status: message.dig(:history_context, :status)&.to_s&.downcase,
        media_type: media_type(message), media_id: media_id(message)
      }.compact
    end
  end

  def business_number
    @business_number ||= params.dig(:entry, 0, :changes, 0, :value, :metadata, :display_phone_number).to_s.gsub(/\D/, '')
  end

  def media_type(message)
    %w[image audio video document sticker].find { |type| message[type.to_sym].present? }
  end

  def media_id(message)
    type = media_type(message)
    type && message.dig(type.to_sym, :id)
  end

  def declined?(errors)
    Array(errors).any? { |error| DECLINED_ERROR_CODES.include?(error.to_h[:code].to_s) }
  end

  def safe_error(errors)
    Array(errors).first.to_h.slice(:code, :title, :message).values.compact.join(': ').gsub(/[\r\n]/, ' ').truncate(500)
  end
end
