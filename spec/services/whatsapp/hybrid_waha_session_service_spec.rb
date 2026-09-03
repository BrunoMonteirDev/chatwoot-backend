require 'rails_helper'

RSpec.describe Whatsapp::HybridWahaSessionService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', phone_number: '+55 44 8856-7632', validate_provider_config: false, sync_templates: false) }
  let(:client) { instance_double(Whatsapp::HybridWahaBridgeClient) }
  let(:service) { described_class.new(channel: channel) }
  let(:connected) { { 'name' => 'hybrid-a1-i5', 'connectionStatus' => 'connected', 'me' => { 'id' => '554488567632@c.us' } } }

  before { allow(Whatsapp::HybridWahaBridgeClient).to receive(:new).and_return(client) }

  it 'creates only through the server-side bridge contract' do
    allow(client).to receive(:session).with(action: :create).and_return('session' => connected)
    expect(service.create!).to eq(connected)
  end

  it 'normalizes matching WhatsApp JIDs before binding' do
    allow(client).to receive(:session).with(action: :status, session: 'hybrid-a1-i5').and_return('session' => connected)
    binding = instance_double(Whatsapp::HybridWahaBindingService, bind!: channel)
    allow(Whatsapp::HybridWahaBindingService).to receive(:new).with(channel: channel, session: 'hybrid-a1-i5').and_return(binding)
    expect(service.bind_connected!('hybrid-a1-i5')).to eq(channel)
  end

  it 'refuses a connected session for another number' do
    allow(client).to receive(:session).with(action: :status, session: 'other').and_return('session' => connected.deep_merge('me' => { 'id' => '5511999999999@c.us' }))
    expect { service.bind_connected!('other') }.to raise_error(Whatsapp::HybridWahaSessionService::Error, /outro número/)
  end

  it 'refuses a session without a determinable phone number' do
    allow(client).to receive(:session).with(action: :status, session: 'unknown').and_return('session' => connected.merge('me' => {}))
    expect { service.bind_connected!('unknown') }.to raise_error(Whatsapp::HybridWahaSessionService::Error, /outro número/)
  end
end
