require 'rails_helper'

describe Whatsapp::HybridWahaBindingService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', hybrid_enabled: false, validate_provider_config: false, sync_templates: false) }
  let(:client) { instance_double(Whatsapp::HybridWahaBridgeClient) }

  before do
    allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config)
    allow(Whatsapp::HybridWahaBridgeClient).to receive(:new).and_return(client)
  end

  it 'persists only after the bridge reserves the session and is idempotent' do
    allow(client).to receive(:binding).with(action: :bind, session: 's1').and_return('ok' => true)
    service = described_class.new(channel: channel, session: 's1')
    expect { service.bind! }.to change { channel.reload.hybrid_waha_session }.from(nil).to('s1')
    service.bind!
    expect(client).to have_received(:binding).with(action: :bind, session: 's1').twice
  end

  it 'does not persist when bridge reservation fails' do
    allow(client).to receive(:binding).with(action: :bind, session: 's1').and_raise(Whatsapp::HybridWahaBridgeClient::Error)
    expect { described_class.new(channel: channel, session: 's1').bind! }.to raise_error(Whatsapp::HybridWahaBridgeClient::Error)
    expect(channel.reload.hybrid_waha_session).to be_nil
  end

  it 'compensates bridge state when Rails persistence fails' do
    allow(client).to receive(:binding).with(action: :bind, session: 's1').and_return('ok' => true)
    allow(channel).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(channel))
    allow(client).to receive(:binding).with(action: :unbind, session: 's1').and_return('ok' => true)
    expect { described_class.new(channel: channel, session: 's1').bind! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(client).to have_received(:binding).with(action: :unbind, session: 's1')
  end

  it 'surfaces a failed compensation' do
    allow(client).to receive(:binding).with(action: :bind, session: 's1').and_return('ok' => true)
    allow(channel).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(channel))
    allow(client).to receive(:binding).with(action: :unbind, session: 's1').and_raise(Whatsapp::HybridWahaBridgeClient::Error)
    expect { described_class.new(channel: channel, session: 's1').bind! }.to raise_error(described_class::CompensationError)
  end

  it 'unbinds without stopping the session and is idempotent' do
    channel.update_columns(hybrid_enabled: true, hybrid_waha_session: 's1')
    allow(client).to receive(:binding).with(action: :unbind).and_return('ok' => true)
    service = described_class.new(channel: channel)
    service.unbind!
    service.unbind!
    expect(channel.reload.hybrid_waha_session).to be_nil
    expect(client).to have_received(:binding).with(action: :unbind).once
  end
end
