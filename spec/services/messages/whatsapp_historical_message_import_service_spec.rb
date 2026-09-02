require 'rails_helper'

describe Messages::WhatsappHistoricalMessageImportService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, last_activity_at: 1.day.ago) }
  let(:timestamp) { 7.days.ago.to_i }
  let(:payload) do
    {
      source_id: 'meta:wamid-history-1', direction: 'incoming', timestamp: timestamp,
      content: 'Mensagem antiga', thread_id: '5511999999999', remote_jid: '5511999999999@s.whatsapp.net',
      quoted_message_id: 'wamid-quoted', history_status: 'read'
    }
  end

  it 'imports silently with the original identity and timestamp' do
    result = described_class.new(account: account, conversation: conversation, payload: payload).perform
    message = result.message

    expect(result.created).to be(true)
    expect(message).to have_attributes(source_id: 'meta:wamid-history-1', message_type: 'incoming', created_at: Time.zone.at(timestamp))
    expect(message.content_attributes).to include(
      'whatsapp_imported_history' => true,
      'whatsapp_transport' => 'meta_cloud',
      'meta_origin' => 'history',
      'in_reply_to_external_id' => 'meta:wamid-quoted'
    )
    expect(conversation.reload.last_activity_at).to be_within(1.second).of(1.day.ago)
  end

  it 'is idempotent for a wamid already received through realtime' do
    existing = create(:message, account: account, conversation: conversation, inbox: inbox, source_id: payload[:source_id])

    result = described_class.new(account: account, conversation: conversation, payload: payload).perform

    expect(result).to have_attributes(created: false, message: existing)
    expect(conversation.messages.where(source_id: payload[:source_id]).count).to eq(1)
  end

  it 'reuses a historical message when the same source_id arrives in realtime' do
    historical = described_class.new(account: account, conversation: conversation, payload: payload).perform.message

    realtime = Messages::MessageBuilder.new(nil, conversation, ActionController::Parameters.new(
      content: 'Mensagem antiga', message_type: 'incoming', source_id: payload[:source_id], idempotent: true
    )).perform

    expect(realtime).to eq(historical)
    expect(account.messages.where(source_id: payload[:source_id]).count).to eq(1)
  end

  it 'imports native Meta history into Channel::Whatsapp with the raw WAMID for realtime convergence' do
    native_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', provider_config: { 'api_key' => 'x', 'phone_number_id' => 'phone', 'business_account_id' => 'waba', 'source' => 'embedded_signup', 'onboarding_mode' => 'coexistence' }, sync_templates: false, validate_provider_config: false)
    native_conversation = create(:conversation, account: account, inbox: native_channel.inbox, contact: contact, contact_inbox: create(:contact_inbox, contact: contact, inbox: native_channel.inbox))
    native_payload = payload.merge(source_id: 'wamid.native-history-1', native_meta: true)

    result = described_class.new(account: account, conversation: native_conversation, payload: native_payload).perform

    expect(result.message).to have_attributes(source_id: 'wamid.native-history-1')
    expect(result.message.external_source_ids).to include('meta' => 'wamid.native-history-1')
  end

  it 'attaches recovered historical media to an already imported message without duplicating it' do
    existing = create(:message, account: account, conversation: conversation, inbox: inbox,
                                source_id: 'waha:3EB0MEDIA', content: nil,
                                content_attributes: { 'historical_media_unavailable' => true })
    attachment = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')

    result = described_class.new(account: account, conversation: conversation, payload: {
      source_id: 'waha:3EB0MEDIA', transport: 'waha', direction: 'incoming', timestamp: timestamp,
      content: '', thread_id: '5511999999999', remote_jid: '5511999999999@c.us', media_type: 'image'
    }, attachment: attachment).perform

    expect(result).to have_attributes(created: false, message: existing)
    expect(existing.reload.attachments.count).to eq(1)
    expect(existing.content_attributes).not_to have_key('historical_media_unavailable')
    expect(conversation.messages.where(source_id: 'waha:3EB0MEDIA').count).to eq(1)
  end

  it 'keeps a readable placeholder when historical media is permanently unavailable' do
    result = described_class.new(account: account, conversation: conversation, payload: {
      source_id: 'waha:3EB0UNAVAILABLE', transport: 'waha', direction: 'incoming', timestamp: timestamp,
      content: '', thread_id: '5511999999999', remote_jid: '5511999999999@c.us', media_type: 'audio',
      historical_media_unavailable: true
    }).perform

    expect(result.message.content).to eq('Mídia indisponível no histórico.')
    expect(result.message.content_attributes).to include('historical_media_unavailable' => true)
  end

  it 'resolves a historical reply when its target already exists' do
    quoted = create(:message, account: account, conversation: conversation, inbox: inbox, source_id: 'meta:wamid-quoted')

    result = described_class.new(account: account, conversation: conversation, payload: payload).perform

    expect(result.message.reload.content_attributes).to include('in_reply_to' => quoted.id, 'in_reply_to_external_id' => quoted.source_id)
  end

  it 'imports a WAHA record silently using its own namespace and group author' do
    result = described_class.new(account: account, conversation: conversation, payload: {
      source_id: 'waha:3EB0HISTORY', transport: 'waha', direction: 'outgoing', timestamp: timestamp,
      content: 'Resposta histórica', thread_id: '120363@g.us', remote_jid: '120363@g.us',
      quoted_message_id: '3EB0QUOTED', chat_type: 'group', participant_jid: '5511999999999@c.us', participant_name: 'Ana'
    }).perform

    expect(result.message).to have_attributes(source_id: 'waha:3EB0HISTORY', message_type: 'outgoing', created_at: Time.zone.at(timestamp))
    expect(result.message.content_attributes).to include(
      'whatsapp_transport' => 'waha', 'waha_origin' => 'history', 'whatsapp_chat_type' => 'group',
      'whatsapp_participant_jid' => '5511999999999@c.us', 'in_reply_to_external_id' => 'waha:3EB0QUOTED'
    )
  end
end
