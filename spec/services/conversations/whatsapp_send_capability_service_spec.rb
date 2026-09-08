require 'rails_helper'

RSpec.describe Conversations::WhatsappSendCapabilityService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: channel.account, inbox: inbox) }

  subject(:capability) { described_class.new(conversation).perform }

  it 'allows freeform messages while the Meta window is open' do
    create(:message, account: channel.account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 2.hours.ago)

    expect(capability).to include(applicable: true, can_send_message: true, can_send_freeform: true,
                                  requires_template: false, template_required: false, send_block_reason: nil,
                                  required_transport: 'meta_cloud', connection_state: 'connected')
  end

  it 'keeps templates available when the Meta window is closed' do
    create(:message, account: channel.account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 25.hours.ago)

    expect(capability).to include(applicable: true, can_send_message: true, can_send_freeform: false,
                                  requires_template: true, template_required: true,
                                  send_block_reason: 'outside_window_template', required_transport: 'meta_cloud',
                                  connection_state: 'connected')
  end

  it 'blocks sending when the native Meta channel requires reauthorization' do
    allow(channel).to receive(:reauthorization_required?).and_return(true)

    expect(capability).to include(applicable: true, can_send_message: false, can_send_freeform: false,
                                  requires_template: false, template_required: false,
                                  send_block_reason: 'reauthorization_required', required_transport: 'meta_cloud',
                                  connection_state: 'disconnected')
  end

  it 'does not apply to non-native WhatsApp inboxes' do
    api_conversation = create(:conversation, account: channel.account)

    expect(described_class.new(api_conversation).perform).to include(applicable: false, can_send_freeform: true,
                                                                       required_transport: nil,
                                                                       connection_state: 'not_applicable')
  end
end
