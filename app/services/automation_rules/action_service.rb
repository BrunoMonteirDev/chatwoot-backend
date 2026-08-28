class AutomationRules::ActionService < ActionService
  def initialize(rule, account, conversation)
    super(conversation)
    @rule = rule
    @account = account
    Current.executed_by = rule
  end

  def perform
    @rule.actions.each do |action|
      @conversation.reload
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @rule.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def send_webhook_event(webhook_url)
    config = Array(webhook_url).first
    config = JSON.parse(config) if config.is_a?(String) && config.strip.start_with?('{')
    if config.is_a?(Hash)
      AutomationRules::WebhookActionJob.perform_later(config, @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}"))
    else
      WebhookJob.perform_later(config, @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}"))
    end
  end

  def update_conversation_attributes(params)
    attributes = Array(params).first
    attributes = JSON.parse(attributes) if attributes.is_a?(String)
    return unless attributes.is_a?(Hash)

    @conversation.update!(custom_attributes: @conversation.custom_attributes.merge(attributes.stringify_keys))
  end

  def update_contact_attributes(params)
    attributes = Array(params).first
    attributes = JSON.parse(attributes) if attributes.is_a?(String)
    return unless attributes.is_a?(Hash)

    contact = @conversation.contact
    contact.update!(custom_attributes: contact.custom_attributes.merge(attributes.stringify_keys))
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])

    teams.each do |team|
      break unless @account.within_email_rate_limit?

      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
      @account.increment_email_sent_count
    end
  end
end
