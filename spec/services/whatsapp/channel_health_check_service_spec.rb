require 'rails_helper'

RSpec.describe Whatsapp::ChannelHealthCheckService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:api_version) { GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0') }
  let(:phone_id) { channel.provider_config['phone_number_id'] }
  let(:waba_id) { channel.provider_config['business_account_id'] }

  before do
    stub_request(:get, "https://graph.facebook.com/#{api_version}/#{waba_id}/phone_numbers")
      .with(query: hash_including('fields' => 'id', 'access_token' => channel.provider_config['api_key']))
      .to_return(status: 200, body: { data: [{ id: phone_id }] }.to_json)
  end

  it 'confirms the configured phone belongs to the configured WABA without sending a message' do
    stub_request(:get, "https://graph.facebook.com/#{api_version}/#{phone_id}")
      .with(query: { 'fields' => 'id', 'access_token' => channel.provider_config['api_key'] })
      .to_return(status: 200, body: { id: phone_id }.to_json)
    expect(described_class.new(channel).perform).to be(true)
  end

  it 'classifies invalid tokens as permanent auth failures' do
    stub_request(:get, "https://graph.facebook.com/#{api_version}/#{phone_id}")
      .with(query: { 'fields' => 'id', 'access_token' => channel.provider_config['api_key'] })
      .to_return(status: 401, body: { error: { code: 190, message: 'Invalid OAuth access token' } }.to_json)

    expect { described_class.new(channel).perform }.to raise_error(described_class::Error) { |error|
      expect(error.kind).to eq(:auth)
      expect(error).to be_permanent
    }
  end

  it 'keeps rate limits transient' do
    stub_request(:get, "https://graph.facebook.com/#{api_version}/#{phone_id}")
      .with(query: { 'fields' => 'id', 'access_token' => channel.provider_config['api_key'] })
      .to_return(status: 429, body: { error: { code: 4, message: 'Rate limit' } }.to_json)

    expect { described_class.new(channel).perform }.to raise_error(described_class::Error) { |error| expect(error.kind).to eq(:rate_limit) }
  end
end
