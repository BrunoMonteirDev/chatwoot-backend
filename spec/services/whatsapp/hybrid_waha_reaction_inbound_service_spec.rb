require 'rails_helper'

RSpec.describe Whatsapp::HybridWahaReactionInboundService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', hybrid_enabled: true, hybrid_waha_session: 'official-session', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, source_id: 'waha:target', content_attributes: { 'whatsapp_transport' => 'waha', 'whatsapp_remote_jid' => '123@g.us', 'whatsapp_provider_message_key' => 'true_123@g.us_target_5544@c.us' }) }

  def perform(payload = {})
    described_class.new(account_id: account.id, inbox_id: inbox.id, channel_id: channel.id, waha_session: 'official-session', payload: { target_message_id: 'target', remote_jid: '123@g.us', sender_id: '5511@c.us', emoji: '👍', event_id: 'event-1' }.merge(payload)).perform
  end

  it 'updates only the scoped target and never creates a message' do
    message
    expect { perform }.not_to change(Message, :count)
    expect(message.reload.content_attributes['whatsapp_reactions']).to contain_exactly(hash_including('sender_id' => '5511@c.us', 'emoji' => '👍', 'transport' => 'waha'))
  end

  it 'supports replacement and removal' do
    message
    perform(emoji: '👍')
    perform(emoji: '❤️')
    perform(emoji: '')
    expect(message.reload.content_attributes['whatsapp_reactions']).to be_empty
  end

  it 'reconciles a from-me WAHA echo with the existing platform reaction' do
    message.update!(content_attributes: message.content_attributes.merge('whatsapp_reactions' => [{
      'sender_id' => 'self', 'emoji' => '👍', 'transport' => 'waha', 'origin' => 'platform'
    }]))

    perform(from_me: true, sender_id: '554488567632@c.us', event_id: 'echo-1')

    expect(message.reload.content_attributes['whatsapp_reactions']).to eq([{
      'sender_id' => 'self', 'emoji' => '👍', 'transport' => 'waha', 'origin' => 'platform', 'event_id' => 'echo-1'
    }])
  end

  it 'ignores a missing target without creating a message' do
    expect { perform(target_message_id: 'missing') }.not_to change(Message, :count)
    expect(perform(target_message_id: 'missing')).to have_attributes(handled: true, message: nil)
  end

  it 'does not resolve a target outside the official inbox' do
    foreign = create(:message, account: account, source_id: 'waha:target', content_attributes: { 'whatsapp_remote_jid' => '123@g.us' })
    expect(perform.message).to be_nil
    expect(foreign.reload.content_attributes['whatsapp_reactions']).to be_nil
  end
end
