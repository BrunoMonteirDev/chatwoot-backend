require 'rails_helper'

describe Whatsapp::HybridWahaInboundService do
  before do
    allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config)
    allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates)
  end
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              provider_config: { 'source' => 'embedded_signup', 'api_key' => 'key', 'phone_number_id' => 'phone' },
                              hybrid_enabled: true, hybrid_waha_session: 'official-session', validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:payload) do
    { external_id: '3EB0', provider_message_key: 'false_group_3EB0', remote_jid: '123@g.us', group_name: 'Equipe', participant_jid: '5511@c.us', participant_name: 'Ana', content: 'olá' }
  end

  def perform(attributes = {})
    described_class.new(account_id: account.id, inbox_id: inbox.id, channel_id: channel.id, waha_session: 'official-session', payload: payload.merge(attributes)).perform
  end

  it 'ignores private WAHA inbound for an official hybrid inbox' do
    result = perform(remote_jid: '5511999999999@c.us')
    expect(result).to have_attributes(handled: true, ignored: true, message: nil)
    expect(Message.count).to eq(0)
  end

  it 'creates one group message in the official inbox and retains WAHA identity' do
    result = perform
    message = result.message
    expect(message.inbox).to eq(inbox)
    expect(message.source_id).to eq('waha:3EB0')
    expect(message.content_attributes).to include('whatsapp_transport' => 'waha', 'whatsapp_provider_message_key' => 'false_group_3EB0', 'whatsapp_participant_jid' => '5511@c.us')
    expect(message.conversation.contact_inbox.source_id).to eq('whatsapp:group:123@g.us')
  end

  it 'deduplicates a repeated group webhook' do
    expect { perform; perform }.to change(Message, :count).by(1)
  end

  it 'does not permit an inbox from another account to consume this binding' do
    result = described_class.new(account_id: create(:account).id, inbox_id: inbox.id, channel_id: channel.id, waha_session: 'official-session', payload: payload).perform
    expect(result.handled).to be_falsey
    expect(Message.count).to eq(0)
  end
end
