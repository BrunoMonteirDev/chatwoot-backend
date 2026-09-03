require 'rails_helper'

describe Whatsapp::Providers::WhatsappCloudStructuredSender do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '5511999999999') }
  let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox, contact_inbox: contact_inbox) }
  let(:message) { create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing, content: 'oi') }
  let(:endpoint) { "https://graph.facebook.com/v13.0/#{channel.provider_config['phone_number_id']}/messages" }

  before { allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config) }

  def send_result
    described_class.new(channel: channel, message: message).perform
  end

  it 'classifies a WAMID response as accepted' do
    stub_request(:post, endpoint).to_return(status: 200, body: { messages: [{ id: 'wamid.ok' }] }.to_json)
    expect(send_result).to have_attributes(status: :accepted, provider_message_id: 'wamid.ok')
  end

  it 'classifies only allowlisted Graph rejections as deterministic' do
    stub_request(:post, endpoint).to_return(status: 400, body: { error: { code: 131047 } }.to_json)
    expect(send_result).to have_attributes(status: :deterministic_rejection, error_code: '131047')
  end

  it 'treats unknown Graph errors, 5xx and malformed responses as ambiguous' do
    [
      [400, { error: { code: 999_999 } }.to_json], [500, { error: { code: 131047 } }.to_json], [200, '{}']
    ].each do |status, body|
      stub_request(:post, endpoint).to_return(status: status, body: body)
      expect(send_result.ambiguous_failure?).to be true
    end
  end

  it 'treats timeout, network and unknown exceptions as ambiguous' do
    [Timeout::Error, Errno::ECONNRESET, RuntimeError].each do |error|
      stub_request(:post, endpoint).to_raise(error)
      expect(send_result.ambiguous_failure?).to be true
    end
  end
end
