require 'rails_helper'

describe Whatsapp::HybridWahaEchoReconciliationService do
  before do
    allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config)
    allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates)
  end

  let(:token) { '3EB0456BD04A09BFABF2FE' }
  let(:wamid) { "wamid.#{Base64.strict_encode64("prefix #{token} suffix")}" }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', hybrid_enabled: true, hybrid_waha_session: 'official-session',
                              provider_config: { 'api_key' => 'key', 'phone_number_id' => 'phone' }, validate_provider_config: false)
  end
  let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox) }
  let!(:message) { create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing, status: :sent, source_id: "waha:#{token}") }

  it 'reconciles the reliable WAHA token embedded in the Meta echo without creating another message' do
    expect { described_class.new(inbox: channel.inbox, meta_source_id: wamid).perform }.not_to change(Message, :count)
    expect(message.reload).to have_attributes(source_id: "waha:#{token}", status: 'delivered')
    expect(message.external_source_ids).to include('meta_cloud' => wamid)
  end

  it 'is idempotent when Meta repeats the echo' do
    service = described_class.new(inbox: channel.inbox, meta_source_id: wamid)
    expect { 2.times { service.perform } }.not_to change(Message, :count)
  end

  it 'does not reconcile ordinary Meta delivery without an existing WAHA source id' do
    message.update!(source_id: 'wamid.original')
    expect(described_class.new(inbox: channel.inbox, meta_source_id: wamid).perform).to be_nil
  end
end
