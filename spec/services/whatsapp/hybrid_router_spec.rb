require 'rails_helper'

describe Whatsapp::HybridRouter do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', hybrid_enabled: true, hybrid_waha_session: 's1', validate_provider_config: false, sync_templates: false) }
  let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox) }
  let(:message) { create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing) }

  before { allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config) }

  it 'uses Meta for a private conversation inside the message window' do
    allow(conversation).to receive(:can_reply?).and_return(true)
    expect(described_class.new(channel: channel, conversation: conversation, message: message).route).to have_attributes(transport: :meta_cloud, reason: 'meta_primary')
  end

  it 'blocks outside the window when template is required' do
    allow(conversation).to receive(:can_reply?).and_return(false)
    expect(described_class.new(channel: channel, conversation: conversation, message: message).route).to have_attributes(transport: :blocked, reason: 'outside_window_template')
  end

  it 'uses WAHA outside the window when configured' do
    channel.update_columns(out_of_window_strategy: 'waha')
    allow(conversation).to receive(:can_reply?).and_return(false)
    expect(described_class.new(channel: channel, conversation: conversation, message: message).route).to have_attributes(transport: :waha, reason: 'outside_window_waha')
  end

  it 'uses WAHA for groups without asking Meta window state' do
    contact_inbox = conversation.contact_inbox
    contact_inbox.update_column(:source_id, 'whatsapp:group:123@g.us')
    expect(described_class.new(channel: channel, conversation: conversation, message: message).route).to have_attributes(transport: :waha, reason: 'group_waha')
  end

  it 'preserves legacy Meta routing while hybrid is disabled' do
    channel.update_columns(hybrid_enabled: false, hybrid_waha_session: nil)
    expect(described_class.new(channel: channel, conversation: conversation, message: message).route).to have_attributes(transport: :meta_cloud, reason: 'hybrid_disabled')
  end

  describe 'WAHA replies' do
    let(:bridge) { instance_double(Whatsapp::HybridWahaBridgeClient, dispatch: { 'source_id' => 'waha:reply', 'provider_message_key' => 'true_group_reply' }) }

    before do
      contact_inbox = conversation.contact_inbox
      contact_inbox.update_column(:source_id, 'whatsapp:group:123@g.us')
      allow(Whatsapp::HybridWahaBridgeClient).to receive(:new).and_return(bridge)
    end

    it 'uses the complete provider key from an inbound quoted target' do
      target = create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, source_id: 'waha:inbound', content_attributes: { 'whatsapp_provider_message_key' => 'false_123@g.us_inbound_5511@c.us' })
      message.update!(content_attributes: { 'in_reply_to' => target.id })
      described_class.new(channel: channel, conversation: conversation, message: message).dispatch
      expect(bridge).to have_received(:dispatch).with(hash_including(payload: hash_including(reply_to: 'false_123@g.us_inbound_5511@c.us')))
    end

    it 'uses the complete provider key from an outbound quoted target' do
      target = create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, source_id: 'waha:outbound', content_attributes: { 'whatsapp_provider_message_key' => 'true_123@g.us_outbound_5544@c.us' })
      message.update!(content_attributes: { 'in_reply_to' => target.id })
      described_class.new(channel: channel, conversation: conversation, message: message).dispatch
      expect(bridge).to have_received(:dispatch).with(hash_including(payload: hash_including(reply_to: 'true_123@g.us_outbound_5544@c.us')))
    end

    it 'fails safely when the quoted target has no provider key' do
      target = create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation)
      message.update!(content_attributes: { 'in_reply_to' => target.id })
      expect { described_class.new(channel: channel, conversation: conversation, message: message).dispatch }
        .to raise_error(Whatsapp::HybridRouter::Error, /provider key/)
      expect(bridge).not_to have_received(:dispatch)
    end

    it 'preserves a normal WAHA message without a reply target' do
      described_class.new(channel: channel, conversation: conversation, message: message).dispatch
      expect(bridge).to have_received(:dispatch).with(hash_including(payload: hash_including(reply_to: nil)))
    end
  end

  context 'when Meta is attempted in hybrid mode' do
    let(:sender) { instance_double(Whatsapp::Providers::WhatsappCloudStructuredSender) }
    let(:bridge) { instance_double(Whatsapp::HybridWahaBridgeClient) }

    before do
      allow(conversation).to receive(:can_reply?).and_return(true)
      allow(Whatsapp::Providers::WhatsappCloudStructuredSender).to receive(:new).and_return(sender)
      allow(Whatsapp::HybridWahaBridgeClient).to receive(:new).and_return(bridge)
    end

    it 'does not call WAHA after accepted Meta delivery' do
      allow(sender).to receive(:perform).and_return(Whatsapp::SendResult.new(status: :accepted, provider_message_id: 'wamid.ok'))
      expect(bridge).not_to receive(:dispatch)
      described_class.new(channel: channel, conversation: conversation, message: message).dispatch { nil }
    end

    it 'blocks deterministic rejection when configured' do
      allow(sender).to receive(:perform).and_return(Whatsapp::SendResult.new(status: :deterministic_rejection))
      expect(bridge).not_to receive(:dispatch)
      expect { described_class.new(channel: channel, conversation: conversation, message: message).dispatch { nil } }.to raise_error(Whatsapp::HybridRouter::Error, /blocked/)
    end

    it 'never falls back for ambiguous Meta results' do
      channel.update_columns(meta_failure_strategy: 'waha')
      allow(sender).to receive(:perform).and_return(Whatsapp::SendResult.new(status: :ambiguous_failure, reason: 'timeout'))
      expect(bridge).not_to receive(:dispatch)
      expect { described_class.new(channel: channel, conversation: conversation, message: message).dispatch { nil } }.to raise_error(Whatsapp::HybridRouter::Error, /uncertain/)
    end
  end
end
