class Webhooks::WhatsappEventsJob < MutexApplicationJob
  queue_as :low
  # Retry budget (19 × 2s = 38s) must exceed the 30s lock TTL set in `perform`, otherwise
  # a webhook that arrives just after the lock is acquired can exhaust retries before the
  # holder finishes and silently drop its message.
  retry_on LockAcquisitionError, wait: 2.seconds, attempts: 20

  def perform(params = {})
    channel = find_channel_from_whatsapp_business_payload(params)

    return handle_history(channel, params) if history_event?(params)
    return handle_account_update(channel, params) if account_update_event?(params)

    if channel_is_inactive?(channel)
      Rails.logger.warn("Inactive WhatsApp channel: #{channel&.phone_number || "unknown - #{params[:phone_number]}"}")
      return
    end

    sender_id = contact_sender_id(params)
    return process_events(channel, params) if sender_id.blank?

    # Album uploads arrive as separate concurrent webhooks. Serialize per (inbox, contact)
    # so the first webhook creates the conversation and the rest append to it.
    # 30s TTL covers the attachment download + transaction — the default 1s expires
    # mid-processing and lets a concurrent webhook re-acquire before the first commit.
    key = format(::Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: sender_id)
    with_lock(key, 30.seconds) do
      process_events(channel, params)
    end
  end

  def history_event?(params)
    params.dig(:entry, 0, :changes, 0, :field) == 'history'
  end

  # History is a Coexistence-only native flow. Require both the configured
  # phone number and WABA entry id before queuing anything; a payload for a
  # sibling WABA must never create contacts or messages in this inbox.
  def handle_history(channel, params)
    return unless native_history_channel?(channel, params)

    Whatsapp::HistoryWebhookParser.new(params).events.each do |event|
      next unless event[:phone_number_id].to_s == channel.provider_config['phone_number_id'].to_s

      Channels::Whatsapp::HistoryChunkImportJob.perform_later(channel, event)
    end
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP_HISTORY] Webhook ignored channel_id=#{channel&.id}: #{e.message}")
  end

  def process_events(channel, params)
    if reaction_event?(params)
      handle_reaction(channel, params)
    elsif message_echo_event?(params)
      handle_message_echo(channel, params)
    else
      handle_message_events(channel, params)
    end
  end

  # Account lifecycle updates have no message sender and must never enter the
  # incoming-message parser. Meta can add fields over time, so only known strong
  # signals change state; unknown events are recorded safely and ignored.
  def account_update_event?(params)
    params.dig(:entry, 0, :changes, 0, :field) == 'account_update'
  end

  def handle_account_update(channel, params)
    return if channel.blank? || channel.provider != 'whatsapp_cloud' || !channel.account.active?

    event = account_update_name(params)
    return if event.blank?

    state = Whatsapp::OperationalStateService.new(channel)
    case event
    when 'ACCOUNT_OFFBOARDED', 'PARTNER_REMOVED'
      state.update!(state: 'disconnected', event: event, error: safe_account_update_reason(params))
    when 'ACCOUNT_RECONNECTED'
      state.update!(state: 'connecting', event: event, error: nil)
      Channels::Whatsapp::ConnectionCheckJob.perform_later(channel)
    else
      Rails.logger.info("[WHATSAPP] Ignored account_update channel_id=#{channel.id} inbox_id=#{channel.inbox&.id} event=#{event}")
    end
  end

  def reaction_event?(params)
    params.dig(:entry, 0, :changes, 0, :value, :messages, 0, :type) == 'reaction'
  end

  def handle_reaction(channel, params)
    reaction_message = params.dig(:entry, 0, :changes, 0, :value, :messages, 0) || {}
    reaction = reaction_message[:reaction] || {}
    # Meta omits `emoji` entirely when a user removes a reaction. An absent
    # emoji is therefore the same removal operation as an empty emoji.
    return unless reaction[:message_id].present? && reaction_message[:from].present?
    target = channel.inbox.messages.find_by(source_id: reaction[:message_id])
    if target.blank?
      Rails.logger.info('[whatsapp] reaction target ignored', channel_id: channel.id, inbox_id: channel.inbox.id, target_wamid: reaction[:message_id])
      return
    end

    Messages::WhatsappReactionUpdateService.new(
      target,
      sender_id: "contact:#{reaction_message[:from]}", emoji: reaction[:emoji].to_s,
      transport: 'meta_cloud', origin: 'contact', event_id: reaction_message[:id]
    ).perform
  rescue ArgumentError => e
    Rails.logger.warn("[WHATSAPP] Ignored reaction: #{e.message}")
  end

  # Detects if the webhook is an SMB message echo event (message sent from WhatsApp Business app)
  # This is part of WhatsApp coexistence feature where businesses can respond from both
  # Chatwoot and the WhatsApp Business app, with messages synced to Chatwoot.
  #
  # Regular message payload (field: "messages"):
  # {
  #   "entry": [{
  #     "changes": [{
  #       "field": "messages",
  #       "value": {
  #         "contacts": [{ "wa_id": "919745786257", "profile": { "name": "Customer" } }],
  #         "messages": [{ "from": "919745786257", "id": "wamid...", "text": { "body": "Hello" } }]
  #       }
  #     }]
  #   }]
  # }
  #
  # Echo message payload (field: "smb_message_echoes"):
  # {
  #   "entry": [{
  #     "changes": [{
  #       "field": "smb_message_echoes",
  #       "value": {
  #         "message_echoes": [{ "from": "971545296927", "to": "919745786257", "id": "wamid...", "text": { "body": "Hi" } }]
  #       }
  #     }]
  #   }]
  # }
  #
  # Key differences:
  # - field: "smb_message_echoes" instead of "messages"
  # - message_echoes[] instead of messages[]
  # - "from" is the business number, "to" is the contact (reversed from regular messages)
  # - No "contacts" array in echo payload
  def message_echo_event?(params)
    params.dig(:entry, 0, :changes, 0, :field) == 'smb_message_echoes'
  end

  def handle_message_echo(channel, params)
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params, outgoing_echo: true).perform
  end

  def handle_message_events(channel, params)
    case channel.provider
    when 'whatsapp_cloud'
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform
    else
      Whatsapp::IncomingMessageService.new(inbox: channel.inbox, params: params).perform
    end
  end

  private

  # Echo payloads reverse the fields — `from` is the business number and `to` is the contact.
  # Returns nil for status-only webhooks so they bypass the lock.
  def contact_sender_id(params)
    value = params.dig(:entry, 0, :changes, 0, :value) || params
    return contact_sender_id_from_message_echoes(value[:message_echoes]) if value[:message_echoes].present?

    contact_sender_id_from_messages(value[:messages], value[:contacts])
  end

  # Echo payloads are outbound messages from the WhatsApp Business app, so `to`
  # points to the contact. Prefer parent BSUID when present so payloads that have
  # both regular+parent BSUIDs serialize with parent-BSUID-only payloads.
  def contact_sender_id_from_message_echoes(message_echoes)
    message = message_echoes&.first
    return if message.blank?

    [message[:to_parent_user_id], message[:to_user_id], message[:to]].compact_blank.first
  end

  # Regular inbound payloads are sent by the contact, so `from` points to the
  # contact. Prefer parent BSUID when present so payloads that have both
  # regular+parent BSUIDs serialize with parent-BSUID-only payloads.
  def contact_sender_id_from_messages(messages, contacts)
    message = messages&.first
    return if message.blank?

    contact = contacts&.first || {}

    [
      message[:from_parent_user_id],
      contact[:parent_user_id],
      message[:from_user_id],
      contact[:user_id],
      message[:from]
    ].compact_blank.first
  end

  def channel_is_inactive?(channel)
    return true if channel.blank?
    # Only skip for embedded signup when reauth is required; manual flow uses API keys and should still receive webhooks
    return true if channel.reauthorization_required? && embedded_signup_channel?(channel)
    return true unless channel.account.active?

    false
  end

  def embedded_signup_channel?(channel)
    (channel.provider_config || {}).to_h['source'] == 'embedded_signup'
  end

  def find_channel_by_url_param(params)
    return unless params[:phone_number]

    Channel::Whatsapp.find_by(phone_number: params[:phone_number])
  end

  def find_channel_from_whatsapp_business_payload(params)
    # for the case where facebook cloud api support multiple numbers for a single app
    # https://github.com/chatwoot/chatwoot/issues/4712#issuecomment-1173838350
    # we will give priority to the phone_number in the payload
    return get_channel_from_wb_payload(params) if params[:object] == 'whatsapp_business_account'

    find_channel_by_url_param(params)
  end

  def get_channel_from_wb_payload(wb_params)
    metadata = wb_params[:entry].first[:changes].first.dig(:value, :metadata) || {}
    return channel_from_waba_id(wb_params) if metadata[:phone_number_id].blank?

    Whatsapp::WebhookChannelFinderService.new(
      display_phone_number: metadata[:display_phone_number],
      phone_number_id: metadata[:phone_number_id]
    ).perform
  end

  def channel_from_waba_id(wb_params)
    waba_id = wb_params.dig(:entry, 0, :id).to_s
    return if waba_id.blank?

    # A WABA can contain more than one inbox. account_update is only actionable
    # when it resolves to exactly one configured channel; ambiguity is logged and
    # deliberately does not leak state between inboxes.
    channels = Channel::Whatsapp.where(provider: 'whatsapp_cloud')
                                .where("provider_config->>'business_account_id' = ?", waba_id)
                                .limit(2)
    return channels.first if channels.one?

    Rails.logger.warn("[WHATSAPP] Ignored ambiguous account_update waba_id=#{waba_id}") if channels.many?
    nil
  end

  def native_history_channel?(channel, params)
    return false unless channel&.history_eligible? && channel.account.active?

    params.dig(:entry, 0, :id).to_s == channel.provider_config['business_account_id'].to_s
  end

  def account_update_name(params)
    value = params.dig(:entry, 0, :changes, 0, :value) || {}
    raw = value[:event] || value[:type] || value[:status] || value.dig(:account_update, :event)
    raw.to_s.upcase.presence
  end

  def safe_account_update_reason(params)
    value = params.dig(:entry, 0, :changes, 0, :value) || {}
    raw = value[:reason] || value[:message] || value.dig(:error, :message)
    raw.to_s.gsub(/[\r\n]/, ' ').truncate(500).presence
  end
end

Webhooks::WhatsappEventsJob.prepend_mod_with('Webhooks::WhatsappEventsJob')
