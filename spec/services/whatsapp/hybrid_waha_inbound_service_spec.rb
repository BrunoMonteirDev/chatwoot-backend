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

  it 'reconciles a private outgoing echo with the existing Chatwoot message' do
    conversation = create(:conversation, account: account, inbox: inbox)
    outgoing = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, source_id: 'waha:3EB0')

    expect { perform(remote_jid: '5511999999999@c.us', from_me: true) }.not_to change(Message, :count)
    expect(perform(remote_jid: '5511999999999@c.us', from_me: true).message).to eq(outgoing)
  end

  it 'creates one group message in the official inbox and retains WAHA identity' do
    result = perform
    message = result.message
    expect(message.inbox).to eq(inbox)
    expect(message.source_id).to eq('waha:3EB0')
    expect(message.content_attributes).to include('whatsapp_transport' => 'waha', 'whatsapp_provider_message_key' => 'false_group_3EB0', 'whatsapp_participant_jid' => '5511@c.us')
    expect(message.conversation.contact_inbox.source_id).to eq('whatsapp:group:123@g.us')
  end

  it 'creates a new group message with its account-scoped participant Contact as sender' do
    participant = create(:contact, account: account, name: 'Ana')
    message = perform(participant_contact_id: participant.id).message
    expect(message.sender).to eq(participant)
    expect(message.content).to eq('olá')
  end

  it 'does not accept a participant Contact from another account' do
    foreign = create(:contact, account: create(:account))
    message = perform(participant_contact_id: foreign.id).message
    expect(message.sender).to eq(message.conversation.contact)
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
