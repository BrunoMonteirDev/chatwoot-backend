require 'rails_helper'

RSpec.describe Conversations::ListDataPreloader do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, agent_last_seen_at: 1.hour.ago) }

  it 'preloads latest, latest non-activity and capped unread count for the list serializer' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'older')
    11.times { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming) }
    activity = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :activity)

    described_class.new([conversation]).perform

    expect(conversation).to be_list_data_preloaded
    expect(conversation.list_latest_message).to eq(activity)
    expect(conversation.list_latest_chat_message).to eq(conversation.messages.incoming.last)
    expect(conversation.list_unread_count).to eq(10)
  end

  it 'uses a bounded number of SQL queries as the page grows' do
    conversations = create_list(:conversation, 20, account: account, inbox: inbox)
    conversations.each { |item| create(:message, account: account, inbox: inbox, conversation: item, message_type: :incoming) }
    queries = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      queries << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { described_class.new(conversations).perform }

    expect(queries.length).to be <= 15
  end
end
