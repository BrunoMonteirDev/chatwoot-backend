require 'rails_helper'

RSpec.describe 'Hybrid WAHA inbox configuration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:headers) { admin.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/hybrid_waha_configuration" }

  before { allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config) }

  it 'returns safe configuration without exposing a bridge secret' do
    get path, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('hybrid_enabled' => false, 'out_of_window_strategy' => 'template', 'meta_failure_strategy' => 'block')
    expect(response.body).not_to include('HYBRID_WAHA_BRIDGE_SECRET')
  end

  it 'updates only validated settings and never accepts a browser-provided session' do
    patch path, params: {
      hybrid_enabled: true, out_of_window_strategy: 'waha', meta_failure_strategy: 'waha', hybrid_waha_session: 'attacker-session'
    }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(channel.reload).to have_attributes(hybrid_enabled: true, out_of_window_strategy: 'waha', meta_failure_strategy: 'waha', hybrid_waha_session: nil)
  end

  it 'rejects invalid enums' do
    patch path, params: { out_of_window_strategy: 'unsafe' }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(channel.reload.out_of_window_strategy).to eq('template')
  end

  it 'does not expose configuration across accounts' do
    other_account = create(:account)
    other_admin = create(:user, account: other_account, role: :administrator)

    get path, headers: other_admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
