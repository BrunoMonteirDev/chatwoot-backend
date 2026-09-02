require 'rails_helper'

RSpec.describe Channels::Whatsapp::ConnectionCheckJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:health_check) { instance_double(Whatsapp::ChannelHealthCheckService) }

  before do
    allow(Whatsapp::ChannelHealthCheckService).to receive(:new).with(channel).and_return(health_check)
  end

  it 'sets the operational state connected after Graph confirms the resources' do
    allow(health_check).to receive(:perform).and_return(true)

    described_class.perform_now(channel)

    expect(channel.reload.meta_connection_status).to eq('connected')
    expect(channel.meta_connection_last_checked_at).to be_present
    expect(channel.meta_connection_last_error).to be_nil
  end

  it 'marks permanent Graph failures disconnected' do
    allow(health_check).to receive(:perform).and_raise(Whatsapp::ChannelHealthCheckService::Error.new('invalid token', kind: :auth))

    described_class.perform_now(channel)

    expect(channel.reload.meta_connection_status).to eq('disconnected')
    expect(channel.meta_connection_last_error).to eq('invalid token')
  end

  it 'does not turn a timeout into a permanent disconnect' do
    allow(health_check).to receive(:perform).and_raise(Whatsapp::ChannelHealthCheckService::Error.new('timeout', kind: :transient))

    described_class.perform_now(channel)

    expect(channel.reload.meta_connection_status).to eq('error')
  end
end
