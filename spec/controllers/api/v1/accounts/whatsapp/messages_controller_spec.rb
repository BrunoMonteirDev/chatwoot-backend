require 'rails_helper'

RSpec.describe 'WhatsApp message mutations API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { create(:inbox, account: account, channel: api_channel) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:message) do
    create(:message, account: account, conversation: conversation, source_id: 'waha:synthetic-message', content: 'Original')
  end

  def mutate(action, params)
    post "/api/v1/accounts/#{account.id}/whatsapp/messages/#{action}",
         params: params,
         headers: agent.create_new_auth_token,
         as: :json
  end

  it 'updates and broadcasts the persisted message without replacing its original content on revoke' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    mutate('revoke', source_id: message.source_id, inbox_id: inbox.id)

    expect(response).to have_http_status(:ok)
    expect(message.reload).to have_attributes(content: 'Original')
    expect(message.content_attributes).to include('whatsapp_revoked' => true, 'whatsapp_previous_content' => 'Original')
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
      'message.updated', kind_of(Time), hash_including(message: message)
    )
  end

  it 'scopes an external mutation to the supplied account and inbox' do
    other_inbox = create(:inbox, account: account, channel: create(:channel_api, account: account))
    other_conversation = create(:conversation, account: account, inbox: other_inbox)
    other_message = create(
      :message, account: account, conversation: other_conversation, source_id: message.source_id, content: 'Other'
    )

    mutate('edit', source_id: message.source_id, inbox_id: other_inbox.id, content: 'Edited only there')

    expect(response).to have_http_status(:ok)
    expect(other_message.reload.content).to eq('Edited only there')
    expect(message.reload.content).to eq('Original')
  end

  it 'rejects an inbox from another account without changing either message' do
    foreign_account = create(:account)
    foreign_inbox = create(:inbox, account: foreign_account, channel: create(:channel_api, account: foreign_account))

    mutate('revoke', source_id: message.source_id, inbox_id: foreign_inbox.id)

    expect(response).to have_http_status(:not_found)
    expect(message.reload.content_attributes['whatsapp_revoked']).not_to be(true)
  end
end
