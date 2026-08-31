class ConversationBuilder
  pattr_initialize [:params!, :contact_inbox!]

  def perform
    return find_or_create_idempotently if params[:idempotent] == true

    look_up_exising_conversation || create_new_conversation
  end

  private

  def look_up_exising_conversation
    return unless @contact_inbox.inbox.lock_to_single_conversation?

    @contact_inbox.conversations.last
  end

  def create_new_conversation
    ::Conversation.create!(conversation_params)
  end

  # The API and public endpoints normally allow users to intentionally open
  # multiple threads. Opt-in callers (the WhatsApp bridge and its frontend)
  # instead need one stable thread per contact and inbox. Lock the contact row
  # so this check and possible creation are atomic across processes.
  def find_or_create_idempotently
    @contact_inbox.contact.with_lock do
      @contact_inbox.contact.conversations
                    .where(inbox_id: @contact_inbox.inbox_id)
                    .order(last_activity_at: :desc, id: :desc)
                    .first || create_new_conversation
    end
  end

  def conversation_params
    additional_attributes = params[:additional_attributes]&.permit! || {}
    custom_attributes = params[:custom_attributes]&.permit! || {}
    status = params[:status].present? ? { status: params[:status] } : {}

    # TODO: temporary fallback for the old bot status in conversation, we will remove after couple of releases
    # commenting this out to see if there are any errors, if not we can remove this in subsequent releases
    # status = { status: 'pending' } if status[:status] == 'bot'
    {
      account_id: @contact_inbox.inbox.account_id,
      inbox_id: @contact_inbox.inbox_id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: additional_attributes,
      custom_attributes: custom_attributes,
      snoozed_until: params[:snoozed_until],
      assignee_id: params[:assignee_id],
      team_id: params[:team_id]
    }.merge(status)
  end
end
