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
