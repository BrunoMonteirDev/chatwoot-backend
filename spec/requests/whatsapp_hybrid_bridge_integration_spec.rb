require 'rails_helper'

# Opt-in local integration: the bridge runs real HTTP handlers with a fake
# WAHA adapter, so these requests never contact a phone or Meta account.
RSpec.describe 'Native hybrid Rails to bridge contract', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, phone_number: '+5511999999999', provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:base) { "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}" }

  before do
    skip 'Run through bridge/hybridRoutes.test.ts with HYBRID_RAILS_CONTAINER' unless ENV['HYBRID_INTEGRATION'] == '1'
    WebMock.disable_net_connect!(allow: URI(ENV.fetch('HYBRID_WAHA_BRIDGE_URL')).host)
    allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config)
  end

  after { WebMock.disable_net_connect!(allow_localhost: true) }

  it 'creates, binds, saves, reloads, dispatches and unbinds through signed bridge HTTP' do
    headers = admin.create_new_auth_token
    get "#{base}/hybrid_waha_configuration", headers: headers
    expect(response.parsed_body).to include('hybrid_enabled' => false, 'out_of_window_strategy' => 'template', 'meta_failure_strategy' => 'block')

    post "#{base}/hybrid_waha_sessions", headers: headers
    expect(response).to have_http_status(:created)
    session = response.parsed_body.fetch('session').fetch('name')
    post "#{base}/hybrid_waha_binding", params: { waha_session: session }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('waha_status' => 'connected')

    patch "#{base}/hybrid_waha_configuration", params: { hybrid_enabled: true, out_of_window_strategy: 'waha', meta_failure_strategy: 'waha' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/hybrid_waha_configuration", headers: headers
    expect(response.parsed_body).to include('waha_session' => session, 'out_of_window_strategy' => 'waha', 'meta_failure_strategy' => 'waha')

    conversation = create(:conversation, account: account, inbox: channel.reload.inbox)
    expect(Conversations::WhatsappSendCapabilityService.new(conversation).perform).to include(required_transport: 'waha', can_send_freeform: true)
    message = create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing, source_id: nil)
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    expect(message.reload.source_id).to start_with('waha:')

    delete "#{base}/hybrid_waha_binding", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(channel.reload.hybrid_waha_session).to be_nil
    get "#{base}/hybrid_waha_sessions", headers: headers
    expect(response.parsed_body.fetch('sessions').map { |item| item['name'] }).to include(session)
    expect(Conversations::WhatsappSendCapabilityService.new(conversation.reload).perform).to include(send_block_reason: 'outside_window_template')
  end
end
