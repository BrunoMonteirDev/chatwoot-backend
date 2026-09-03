require 'rails_helper'

describe Whatsapp::HybridWahaBridgeClient do
  before do
    allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config)
    allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates)
  end
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', provider_config: { 'source' => 'embedded_signup', 'api_key' => 'key', 'phone_number_id' => 'phone' }, hybrid_enabled: true, hybrid_waha_session: 'official-session', validate_provider_config: false)
  end
  let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox) }
  let(:message) { create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation) }

  around do |example|
    ClimateControl.modify HYBRID_WAHA_BRIDGE_URL: 'http://bridge.test', HYBRID_WAHA_BRIDGE_SECRET: 'test-secret' do
      example.run
    end
  end

  it 'sends only internal identifiers through the signed bridge contract' do
    response = instance_double(Net::HTTPOK, body: '{"ok":true}', is_a?: true)
    allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))
    result = described_class.new(channel: channel).dispatch(operation: :text, conversation: conversation, message: message, payload: { remote_jid: '123@g.us', content: 'oi' })
    expect(result).to eq('ok' => true)
    expect(Net::HTTP).to have_received(:start)
  end

  it 'does not operate when hybrid mode is disabled' do
    channel.update!(hybrid_enabled: false, hybrid_waha_session: nil)
    expect { described_class.new(channel: channel).dispatch(operation: :text, conversation: conversation, message: message) }.to raise_error(Whatsapp::HybridWahaBridgeClient::Error)
  end
end
