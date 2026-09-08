require 'rails_helper'

RSpec.describe Conversations::WhatsappSendCapabilityService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox) }
  let(:bridge) { instance_double(Whatsapp::HybridWahaBridgeClient, binding: { 'status' => 'connected' }) }

  before { allow(Whatsapp::HybridWahaBridgeClient).to receive(:new).and_return(bridge) }

  it 'requires templates by default and does not consult WAHA' do
    expect(described_class.new(conversation).perform).to include(send_block_reason: 'outside_window_template', required_transport: 'meta_cloud')
    expect(bridge).not_to have_received(:binding)
  end

  it 'allows WAHA freeform only after explicit enabled binding and strategy, including reload' do
    channel.update_columns(hybrid_enabled: true, hybrid_waha_session: 's1', out_of_window_strategy: 'waha')
    expect(described_class.new(conversation.reload).perform).to include(can_send_freeform: true, required_transport: 'waha', requires_template: false)
    channel.update_columns(hybrid_enabled: false)
    expect(described_class.new(conversation.reload).perform).to include(send_block_reason: 'outside_window_template')
  end

  it 'blocks configured WAHA when the session is offline' do
    channel.update_columns(hybrid_enabled: true, hybrid_waha_session: 's1', out_of_window_strategy: 'waha')
    allow(bridge).to receive(:binding).and_return('status' => 'disconnected')
    expect(described_class.new(conversation.reload).perform).to include(can_send_freeform: false, required_transport: 'waha', send_block_reason: 'waha_disconnected')
  end

  it 'preserves Meta while the window is open, even with WAHA fallback configured' do
    channel.update_columns(hybrid_enabled: true, hybrid_waha_session: 's1', out_of_window_strategy: 'waha')
    create(:message, conversation: conversation, account: channel.account, inbox: channel.inbox, message_type: :incoming)
    expect(described_class.new(conversation.reload).perform).to include(can_send_freeform: true, required_transport: 'meta_cloud')
    expect(bridge).not_to have_received(:binding)
  end
end
