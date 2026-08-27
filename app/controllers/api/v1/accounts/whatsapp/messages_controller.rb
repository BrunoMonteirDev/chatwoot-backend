class Api::V1::Accounts::Whatsapp::MessagesController < Api::V1::Accounts::BaseController
  def status
    message = Current.account.messages.find_by!(source_id: status_params[:source_id])
    Messages::StatusUpdateService.new(message, status_params[:status], status_params[:external_error]).perform
    render json: { id: message.id, status: message.status }
  end

  def reaction
    message = Current.account.messages.find_by!(source_id: reaction_params[:source_id])
    return render json: { error: 'Reaction update is only allowed for API inboxes' }, status: :forbidden unless message.conversation.inbox.api?

    Messages::WhatsappReactionUpdateService.new(message, reaction_params[:reaction].to_h).perform
    render json: { id: message.id, conversation_id: message.conversation_id, content_attributes: message.content_attributes }
  end

  # These endpoints are deliberately separate from the ordinary Chatwoot
  # message update/delete endpoints. They are only called by the bridge after
  # the transport accepted an edit or a delete-for-everyone operation.
  def edit
    message = mutation_message
    Messages::WhatsappMessageMutationService.new(message).edit!(mutation_params[:content])
    render json: mutation_response(message)
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def revoke
    message = mutation_message
    Messages::WhatsappMessageMutationService.new(message).revoke!
    render json: mutation_response(message)
  end

  # The bridge uses this small, account-scoped lookup to construct an exact
  # Baileys quoted key for group replies (remote JID/fromMe/participant).
  # It intentionally returns no message body or attachment data.
  def target
    message = Current.account.messages.find_by!(source_id: params.require(:source_id))
    render json: {
      id: message.id,
      conversation_id: message.conversation_id,
      source_id: message.source_id,
      content_attributes: message.content_attributes,
      attachments_count: message.attachments.count
    }
  end

  private

  def status_params
    params.permit(:source_id, :status, :external_error)
  end

  def reaction_params
    params.permit(:source_id, reaction: [:sender_id, :emoji, :transport, :origin, :event_id])
  end

  def mutation_params
    params.permit(:source_id, :content)
  end

  def mutation_message
    message = Current.account.messages.find_by!(source_id: mutation_params[:source_id])
    raise ActiveRecord::RecordNotFound unless message.conversation.inbox.api?

    message
  end

  def mutation_response(message)
    {
      id: message.id,
      conversation_id: message.conversation_id,
      content: message.content,
      content_attributes: message.content_attributes
    }
  end
end
