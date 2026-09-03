require 'rails_helper'

describe Channel::Whatsapp do
  before { allow_any_instance_of(described_class).to receive(:validate_provider_config) }
  it 'defaults hybrid mode to disabled and requires a session only when enabled' do
    channel = build(:channel_whatsapp, account: create(:account), provider: 'whatsapp_cloud', validate_provider_config: false)
    expect(channel.hybrid_enabled).to be_falsey
    channel.hybrid_enabled = true
    expect(channel).to be_invalid
    channel.hybrid_waha_session = 'session-a'
    expect(channel).to be_valid
  end
end
