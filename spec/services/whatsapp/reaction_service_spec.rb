require 'rails_helper'

RSpec.describe Whatsapp::ReactionService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '5511999999999') }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact_inbox: contact_inbox) }
  let(:message) { create(:message, account: account, inbox: channel.inbox, conversation: conversation, source_id: 'wamid.target') }
  let(:user) { create(:user, account: account) }

  let(:provider) { instance_double(Whatsapp::Providers::WhatsappCloudService, send_reaction: { 'messages' => [{ 'id' => 'wamid.graph' }] }) }

  before { allow(Whatsapp::Providers::WhatsappCloudService).to receive(:new).with(whatsapp_channel: channel).and_return(provider) }

  it 'sends the native Cloud reaction and records only the reaction state' do
    message
    user
    expect { described_class.new(message: message, emoji: '👍', user: user).perform }.not_to change(Message, :count)
    expect(message.reload.content_attributes['whatsapp_reactions']).to contain_exactly(hash_including('sender_id' => 'self', 'emoji' => '👍', 'transport' => 'meta_cloud'))
  end

  it 'uses an empty emoji to remove the platform reaction' do
    described_class.new(message: message, emoji: '👍', user: user).perform
    described_class.new(message: message, emoji: '', user: user).perform
    expect(message.reload.content_attributes['whatsapp_reactions']).to be_empty
  end

  it 'does not persist optimistic state when Graph rejects the reaction' do
    allow(provider).to receive(:send_reaction).and_raise(Whatsapp::Providers::WhatsappCloudService::ReactionError, 'bad target')
    expect { described_class.new(message: message, emoji: '👍', user: user).perform }.to raise_error(described_class::Error, 'bad target')
    expect(message.reload.content_attributes['whatsapp_reactions']).to be_nil
  end

  it 'rejects non-Cloud channels, target IDs without WAMID, and group targets' do
    channel.update!(provider: 'default')
    expect { described_class.new(message: message, emoji: '👍', user: user).perform }.to raise_error(described_class::Error, /Cloud/)
    channel.update!(provider: 'whatsapp_cloud')
    message.update!(source_id: 'evolution:abc')
    expect { described_class.new(message: message, emoji: '👍', user: user).perform }.to raise_error(described_class::Error, /message id/)
    message.update!(source_id: 'wamid.target', content_attributes: { 'whatsapp_remote_jid' => '120363@g.us' })
    expect { described_class.new(message: message, emoji: '👍', user: user).perform }.to raise_error(described_class::Error, /groups/)
  end

  context 'with a hybrid WAHA message' do
    let(:bridge) { instance_double(Whatsapp::HybridWahaBridgeClient, dispatch: { 'ok' => true }) }

    before do
      channel.update_columns(hybrid_enabled: true, hybrid_waha_session: 'session-a')
      message.update!(source_id: 'waha:canonical', content_attributes: { 'whatsapp_transport' => 'waha', 'whatsapp_remote_jid' => '120363@g.us', 'whatsapp_provider_message_key' => 'false_120363@g.us_3EB0FULL' })
      allow(Whatsapp::HybridWahaBridgeClient).to receive(:new).with(channel: channel).and_return(bridge)
    end

    it 'uses the complete WAHA provider key for add, replace and remove' do
      %w[👍 ❤️].each { |emoji| described_class.new(message: message, emoji: emoji, user: user).perform }
      described_class.new(message: message, emoji: '', user: user).perform
      expect(bridge).to have_received(:dispatch).with(hash_including(operation: :reaction, payload: hash_including(target_message_id: 'false_120363@g.us_3EB0FULL'))).exactly(3).times
    end

    it 'fails safely when the legacy WAHA provider key is absent' do
      message.update!(content_attributes: { 'whatsapp_transport' => 'waha', 'whatsapp_remote_jid' => '120363@g.us' })
      expect { described_class.new(message: message, emoji: '👍', user: user).perform }.to raise_error(described_class::Error, /provider message key/)
      expect(bridge).not_to have_received(:dispatch)
    end
  end
end
