require 'rails_helper'

RSpec.describe Messages::ForwardMessageService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:source_inbox) do
    create(:inbox, account: account,
                   channel: build(:channel_api, account: account, additional_attributes: { 'whatsapp_transports' => ['evolution'] }))
  end
  let(:destination_inbox) do
    create(:inbox, account: account,
                   channel: build(:channel_api, account: account, additional_attributes: { 'whatsapp_transports' => ['waha'] }))
  end
  let(:source_conversation) { create(:conversation, account: account, inbox: source_inbox) }
  let(:destination_conversation) { create(:conversation, account: account, inbox: destination_inbox) }
  let(:source_message) { create(:message, account: account, conversation: source_conversation, inbox: source_inbox, content: 'Conteúdo atual') }
  let(:token) { 'b7a0e711-0d51-4b79-9fb6-0f36a833f343' }

  subject(:forward) do
    described_class.new(source_message: source_message, destination_conversation: destination_conversation, user: user, idempotency_token: token).perform
  end

  it 'forwards current text without reply or edit history' do
    source_message.update!(content_attributes: { 'in_reply_to' => 123, 'whatsapp_edited' => true, 'whatsapp_previous_content' => 'Anterior' })

    expect(forward).to have_attributes(conversation: destination_conversation, content: 'Conteúdo atual', message_type: 'outgoing', private: false)
    expect(forward.content_attributes).to include('forwarded_from_message_id' => source_message.id, 'forwarding_token' => token)
    expect(forward.content_attributes).not_to include('in_reply_to', 'whatsapp_edited', 'whatsapp_previous_content')
  end

  it 'reuses a local image blob preserving its metadata' do
    source_message.attachments.create!(account: account, file_type: :image, file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))

    attachment = forward.attachments.first
    expect(attachment.file.blob.id).to eq(source_message.attachments.first.file.blob.id)
    expect(attachment.file.filename.to_s).to eq('avatar.png')
    expect(attachment.file.content_type).to eq('image/png')
    expect(attachment.file.byte_size).to eq(source_message.attachments.first.file.byte_size)
  end

  it 'reuses every local attachment' do
    source_message.attachments.create!(account: account, file_type: :image, file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))
    source_message.attachments.create!(account: account, file_type: :file, file: fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf'))

    expect(forward.attachments.map { |attachment| attachment.file.blob.id }).to eq(source_message.attachments.map { |attachment| attachment.file.blob.id })
  end

  it 'is idempotent for retries' do
    first = forward
    second = described_class.new(source_message: source_message, destination_conversation: destination_conversation, user: user, idempotency_token: token).perform

    expect(second).to eq(first)
    expect(destination_conversation.messages.count { |message| message.content_attributes.to_h['forwarding_token'] == token }).to eq(1)
  end

  it 'rejects an invalid destination' do
    destination_inbox.channel.update!(additional_attributes: {})
    expect { forward }.to raise_error(described_class::Error, 'A conversa de destino não é uma inbox WhatsApp válida.')
  end

  it 'rejects the source conversation as destination' do
    service = described_class.new(source_message: source_message, destination_conversation: source_conversation, user: user, idempotency_token: token)
    expect { service.perform }.to raise_error(described_class::Error, 'Não é possível encaminhar para a própria conversa.')
  end

  it 'rejects revoked and private messages' do
    source_message.update!(content_attributes: { 'whatsapp_revoked' => true })
    expect { forward }.to raise_error(described_class::Error, 'A mensagem não pode ser encaminhada.')

    source_message.update!(content_attributes: {}, private: true)
    expect { forward }.to raise_error(described_class::Error, 'A mensagem não pode ser encaminhada.')
  end

  it 'rejects empty, activity, and template messages' do
    source_message.update!(content: '')
    expect { forward }.to raise_error(described_class::Error, 'A mensagem não pode ser encaminhada.')

    source_message.update!(content: 'Atividade', message_type: :activity)
    expect { forward }.to raise_error(described_class::Error, 'A mensagem não pode ser encaminhada.')

    source_message.update!(message_type: :template)
    expect { forward }.to raise_error(described_class::Error, 'A mensagem não pode ser encaminhada.')
  end

  it 'rejects an attachment that only has an external URL' do
    source_message.update!(content: '')
    source_message.attachments.create!(account: account, file_type: :image, external_url: 'https://example.com/image.png')

    expect { forward }.to raise_error(described_class::Error, 'O anexo não está disponível para encaminhamento.')
  end

  it 'rejects a Meta destination outside its 24 hour window' do
    destination_inbox.channel.update!(additional_attributes: { 'whatsapp_transports' => ['meta_cloud'] })
    create(:message, account: account, conversation: destination_conversation, inbox: destination_inbox, message_type: :incoming, created_at: 24.hours.ago - 1.minute)

    expect { forward }.to raise_error(described_class::Error, 'A janela de 24 horas da Meta Cloud expirou. Use um template.')
  end
end
