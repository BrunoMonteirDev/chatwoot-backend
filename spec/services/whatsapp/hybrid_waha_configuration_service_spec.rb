require 'rails_helper'

RSpec.describe Whatsapp::HybridWahaConfigurationService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }

  it 'persists only the allowed hybrid configuration with conservative defaults' do
    result = described_class.new(
      channel: channel,
      attributes: { hybrid_enabled: true, out_of_window_strategy: 'waha', meta_failure_strategy: 'waha' }
    ).update!

    expect(result).to have_attributes(hybrid_enabled: true, out_of_window_strategy: 'waha', meta_failure_strategy: 'waha')
    expect(result.hybrid_waha_session).to be_nil
  end

  it 'rejects invalid strategies without changing the channel' do
    expect {
      described_class.new(channel: channel, attributes: { out_of_window_strategy: 'anything' }).update!
    }.to raise_error(described_class::Error, /invalid/)

    expect(channel.reload.out_of_window_strategy).to eq('template')
  end

  it 'accepts both conservative strategy values and can disable hybrid mode' do
    described_class.new(channel: channel, attributes: { hybrid_enabled: true, out_of_window_strategy: 'template', meta_failure_strategy: 'block' }).update!
    expect(channel.reload).to have_attributes(hybrid_enabled: true, out_of_window_strategy: 'template', meta_failure_strategy: 'block')

    described_class.new(channel: channel, attributes: { hybrid_enabled: false, out_of_window_strategy: 'waha', meta_failure_strategy: 'waha' }).update!
    expect(channel.reload).to have_attributes(hybrid_enabled: false, out_of_window_strategy: 'waha', meta_failure_strategy: 'waha')
  end

  it 'rejects non-official channels' do
    channel.update_columns(provider: 'default')
    expect {
      described_class.new(channel: channel, attributes: { hybrid_enabled: true }).update!
    }.to raise_error(described_class::Error, /official/)
  end
end
