require 'rails_helper'

describe Whatsapp::HybridRouter do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', hybrid_enabled: true, hybrid_waha_session: 'owned-session', validate_provider_config: false, sync_templates: false) }
  let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox) }
  let(:message) { create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing) }
  let(:bridge) { instance_double(Whatsapp::HybridWahaBridgeClient) }

  before { allow(Whatsapp::HybridWahaBridgeClient).to receive(:new).and_return(bridge) }

  it 'rejects an account mismatch before bridge dispatch' do
    other = create(:account)
    allow(conversation).to receive(:account_id).and_return(other.id)
    expect(bridge).not_to receive(:dispatch)
    expect { described_class.new(channel: channel, conversation: conversation, message: message).send(:waha, 'test') }.to raise_error(described_class::Error, /does not belong/)
  end

  it 'rejects an inbox mismatch before bridge dispatch' do
    allow(conversation).to receive(:inbox_id).and_return(create(:inbox).id)
    expect(bridge).not_to receive(:dispatch)
    expect { described_class.new(channel: channel, conversation: conversation, message: message).send(:waha, 'test') }.to raise_error(described_class::Error, /does not belong/)
  end

  it 'uses only the persisted session and ignores arbitrary payload values' do
    expect(channel.hybrid_waha_session).to eq('owned-session')
    expect { described_class.new(channel: channel, conversation: conversation, message: message).send(:waha, 'test') }.not_to raise_error
  rescue Whatsapp::HybridWahaBridgeClient::Error
    # Construction selected the persisted binding before the intentionally unstubbed bridge call.
    expect(channel.hybrid_waha_session).to eq('owned-session')
  end

  it 'blocks WAHA when hybrid mode is disabled even with a persisted session' do
    channel.update_columns(hybrid_enabled: false)
    expect { described_class.new(channel: channel, conversation: conversation, message: message).send(:waha, 'test') }.to raise_error(described_class::Error, /not enabled/)
  end
end
