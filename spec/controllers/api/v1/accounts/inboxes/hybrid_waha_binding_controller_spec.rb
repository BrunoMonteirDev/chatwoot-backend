require 'rails_helper'

RSpec.describe 'Hybrid WAHA inbox binding', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', hybrid_enabled: true, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:path) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/hybrid_waha_binding" }
  let(:client) { instance_double(Whatsapp::HybridWahaBridgeClient) }

  before do
    allow(Whatsapp::HybridWahaBridgeClient).to receive(:new).and_return(client)
  end

  it 'reports not_bound without calling the bridge' do
    expect(client).not_to receive(:binding)
    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('waha_status' => 'not_bound')
  end

  it 'reports the observed connected or disconnected state without changing the binding' do
    channel.update_columns(hybrid_waha_session: 'session-a')
    allow(client).to receive(:binding).with(action: :status).and_return('status' => 'connected')
    get path, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('waha_status' => 'connected')

    allow(client).to receive(:binding).with(action: :status).and_raise(Whatsapp::HybridWahaBridgeClient::Error)
    get path, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('waha_status' => 'disconnected')
    expect(channel.reload.hybrid_waha_session).to eq('session-a')
  end
end
