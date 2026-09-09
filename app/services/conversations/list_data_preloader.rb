class Conversations::ListDataPreloader
  def initialize(conversations)
    @conversations = conversations.to_a
  end

  def perform
    return @conversations if @conversations.empty?

    ids = @conversations.map(&:id)
    account_id = @conversations.first.account_id
    latest_messages = latest_message_scope(ids, account_id).index_by(&:conversation_id)
    latest_chat_messages = latest_message_scope(ids, account_id).where.not(message_type: :activity).index_by(&:conversation_id)
    unread_counts = unread_counts(ids, account_id)

    @conversations.each do |conversation|
      [latest_messages[conversation.id], latest_chat_messages[conversation.id]].compact.each do |message|
        message.association(:conversation).target = conversation
      end
      conversation.preload_list_data(
        latest_message: latest_messages[conversation.id],
        latest_chat_message: latest_chat_messages[conversation.id],
        unread_count: [unread_counts.fetch(conversation.id, 0), 10].min
      )
    end
  end

  private

  def latest_message_scope(ids, account_id)
    Message.where(account_id: account_id, conversation_id: ids)
           .select('DISTINCT ON (conversation_id) messages.*')
           .reorder('conversation_id, created_at DESC, id DESC')
           .includes(:inbox, :sender, attachments: { file_attachment: :blob }, sender: { avatar_attachment: :blob })
  end

  def unread_counts(ids, account_id)
    Message.incoming.where(account_id: account_id, conversation_id: ids)
           .joins(:conversation)
           .where('messages.created_at > COALESCE(conversations.agent_last_seen_at, ?)', Time.at(0))
           .reorder(nil)
           .group(:conversation_id)
           .count
  end
end
