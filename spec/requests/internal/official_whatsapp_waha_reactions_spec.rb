require 'rails_helper'

RSpec.describe 'Internal official WAHA reactions', type: :request do
  around { |example| ClimateControl.modify HYBRID_WAHA_BRIDGE_SECRET: 'bridge-secret' do example.run end }

  let(:path) { '/internal/official_whatsapp/waha/reaction' }
  let(:body) { { account_id: 1, inbox_id: 5, waha_session: 'hybrid-a1-i5', payload: { target_message_id: 'target', remote_jid: '120@g.us', sender_id: '5511@c.us', emoji: '👍' } }.to_json }
  let(:headers) { Whatsapp::HybridWahaBridgeSigner.headers(method: 'POST', path: path, body: body).merge('CONTENT_TYPE' => 'application/json') }

  it 'accepts only the signed internal reaction contract' do
    service = instance_double(Whatsapp::HybridWahaReactionInboundService, perform: Whatsapp::HybridWahaReactionInboundService::Result.new(handled: true, message: instance_double(Message, id: 77)))
    allow(Whatsapp::HybridWahaReactionInboundService).to receive(:new).and_return(service)

    post path, params: body, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('handled' => true, 'message_id' => 77)
  end

  it 'rejects an unsigned request before service dispatch' do
    expect(Whatsapp::HybridWahaReactionInboundService).not_to receive(:new)
    post path, params: body, headers: { 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end
end
