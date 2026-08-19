require 'rails_helper'

describe Messages::WhatsappMessageTransportUpdateService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) do
    create(:message, account: account, conversation: conversation).tap do |record|
      record.update_column(:content_attributes, { 'custom_integration_value' => 'preserved' })
    end
  end

  it 'records the Evolution source key without removing reply metadata' do
    described_class.new(message, {
      source_id: 'evolution:BAE5', transport: 'evolution', remote_jid: '5511999999999@s.whatsapp.net', from_me: true
    }).perform

    expect(message.reload.source_id).to eq('evolution:BAE5')
    expect(message.content_attributes).to include(
      'custom_integration_value' => 'preserved',
      'whatsapp_transport' => 'evolution',
      'whatsapp_remote_jid' => '5511999999999@s.whatsapp.net',
      'whatsapp_from_me' => true
    )
  end
end
