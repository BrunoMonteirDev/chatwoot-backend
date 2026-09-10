require 'rails_helper'

describe Messages::WhatsappMessageMutationService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation, content: 'Original') }

  it 'edits without dropping transport and reply metadata' do
    message.update!(content_attributes: { 'whatsapp_transport' => 'evolution', 'evolution_quoted_message_id' => 'quoted' })

    described_class.new(message).edit!('Corrigida')

    expect(message.reload.content).to eq('Corrigida')
    expect(message.content_attributes).to include(
      'whatsapp_transport' => 'evolution', 'evolution_quoted_message_id' => 'quoted',
      'whatsapp_edited' => true, 'whatsapp_previous_content' => 'Original'
    )
  end

  it 'revokes idempotently while retaining the external audit metadata' do
    reply_target = create(:message, account: account, conversation: conversation)
    message.update!(content_attributes: { 'whatsapp_transport' => 'evolution', 'in_reply_to' => reply_target.id })

    2.times { described_class.new(message).revoke! }

    expect(message.reload.content).to eq('Original')
    expect(message.content_attributes).to include(
      'whatsapp_transport' => 'evolution', 'in_reply_to' => reply_target.id,
      'whatsapp_revoked' => true, 'whatsapp_previous_content' => 'Original'
    )
  end

  it 'retains attachments when revoking a message' do
    attachment = message.attachments.create!(account: account, file_type: :file)

    described_class.new(message).revoke!

    expect(message.reload.attachments).to contain_exactly(attachment)
  end
end
