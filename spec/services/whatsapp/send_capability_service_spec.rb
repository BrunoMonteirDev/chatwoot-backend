require 'rails_helper'

RSpec.describe Whatsapp::SendCapabilityService do
  let(:conversation) { instance_double(Conversation) }
  let(:inbox) { instance_double(Inbox) }
  let(:channel) { instance_double(Channel::Whatsapp, reauthorization_required?: false, meta_connection_status: 'connected', hybrid_waha_session: 'session') }

  before do
    allow(conversation).to receive(:inbox).and_return(inbox)
    allow(inbox).to receive(:channel).and_return(channel)
    allow(channel).to receive(:is_a?).with(Channel::Whatsapp).and_return(true)
  end

  it 'keeps a Meta conversation editable when router selects Meta' do
    allow(Whatsapp::HybridRouter).to receive(:new).and_return(instance_double(Whatsapp::HybridRouter, route: Whatsapp::HybridRouter::Decision.new(transport: :meta_cloud, reason: 'meta_primary')))
    expect(described_class.new(conversation).perform).to include(can_send_freeform: true, required_transport: 'meta_cloud')
  end

  it 'requires a template when the router blocks outside the service window' do
    allow(Whatsapp::HybridRouter).to receive(:new).and_return(instance_double(Whatsapp::HybridRouter, route: Whatsapp::HybridRouter::Decision.new(transport: :blocked, reason: 'outside_window_template')))
    expect(described_class.new(conversation).perform).to include(can_send_freeform: false, template_required: true, send_block_reason: 'outside_window_template')
  end

  it 'prioritizes Meta reauthorization over routing' do
    allow(channel).to receive(:reauthorization_required?).and_return(true)
    expect(described_class.new(conversation).perform).to include(send_block_reason: 'reauthorization_required', required_transport: 'meta_cloud')
  end
end
