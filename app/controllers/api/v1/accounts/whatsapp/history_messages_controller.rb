class Api::V1::Accounts::Whatsapp::HistoryMessagesController < Api::V1::Accounts::BaseController
  before_action :fetch_conversation
  before_action :ensure_api_inbox

  def create
    result = Messages::WhatsappHistoricalMessageImportService.new(
      account: Current.account,
      conversation: @conversation,
      payload: history_params.to_h,
      attachment: params[:attachment]
    ).perform
    render json: { id: result.message.id, created: result.created }, status: result.created ? :created : :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_conversation
    @conversation = Current.account.conversations.find(params[:conversation_id])
  end

  def ensure_api_inbox
    return if @conversation.inbox.api?

    render json: { error: 'History import is only allowed for API inboxes' }, status: :forbidden
  end

  def history_params
    params.permit(
      :source_id, :direction, :timestamp, :content, :thread_id, :remote_jid,
      :quoted_message_id, :history_status, :status, :media_type,
      :historical_media_unavailable
    )
  end
end
