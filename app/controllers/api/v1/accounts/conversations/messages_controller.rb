class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  include PermissionAuthorization
  before_action -> { require_inbox_permission!(@conversation.inbox, 'conversation_reply') }, only: [:create, :update, :destroy, :retry, :whatsapp_reaction]
  before_action :ensure_api_inbox, only: [:update, :whatsapp_reaction, :whatsapp_transport_metadata]

  def index
    @messages = message_finder.perform
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    ActiveRecord::Base.transaction do
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text, content_attributes: { deleted: true })
      message.attachments.destroy_all
    end
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def whatsapp_reaction
    @message = @conversation.messages.find_by!(source_id: whatsapp_reaction_params[:source_id])
    Messages::WhatsappReactionUpdateService.new(@message, whatsapp_reaction_params[:reaction].to_h).perform
    render :update
  end

  def whatsapp_transport_metadata
    @message = message
    Messages::WhatsappMessageTransportUpdateService.new(@message, whatsapp_transport_metadata_params.to_h).perform
    render :update
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  rescue Google::Cloud::Error => e
    # `details` carries the clean human message; `message` includes gRPC debug noise
    render_could_not_create_error(e.details.presence || e.message)
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error)
  end

  def whatsapp_reaction_params
    params.permit(:source_id, reaction: [:sender_id, :emoji, :transport, :origin, :event_id])
  end

  def whatsapp_transport_metadata_params
    params.permit(:source_id, :transport, :remote_jid, :from_me)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end
