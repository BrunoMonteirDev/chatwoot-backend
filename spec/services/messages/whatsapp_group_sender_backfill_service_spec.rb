require 'rails_helper'

describe Messages::WhatsappGroupSenderBackfillService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:participant) do
    create(:contact, account: account, name: 'Ana', phone_number: '+5511888888888',
                     additional_attributes: { 'waha_lid' => '19696904601705', 'waha_phone' => '+5511888888888' })
  end
  let(:group_contact) do
    create(:contact, account: account, additional_attributes: {
             'whatsapp_chat_type' => 'group', 'whatsapp_group_jid' => '120363@g.us',
             'whatsapp_group_participants' => [{ 'jid' => '19696904601705@lid', 'phone_jid' => '5511888888888@c.us', 'contact_id' => participant.id }]
           })
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: group_contact) }

  it 'reconciles an old incoming group sender without changing or duplicating the message and is idempotent' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: group_contact,
                               message_type: :incoming, content: 'Mensagem original',
                               content_attributes: { 'whatsapp_remote_jid' => '120363@g.us', 'whatsapp_participant_jid' => '19696904601705@lid' })

    first = described_class.new(account: account).perform
    second = described_class.new(account: account).perform

    expect(first).to have_attributes(scanned: 1, updated: 1, unresolved: 0)
    expect(second).to have_attributes(scanned: 1, updated: 0, unresolved: 0)
    expect(message.reload).to have_attributes(sender: participant, content: 'Mensagem original')
    expect(conversation.messages.where(id: message.id).count).to eq(1)
  end

  it 'uses participant history and persisted phone aliases' do
    group_contact.update!(additional_attributes: group_contact.additional_attributes.merge(
      'whatsapp_group_participants' => [],
      'whatsapp_group_participant_history' => [{ 'jid' => 'old@lid', 'phone' => '+5511888888888' }]
    ))
    message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: group_contact,
                               message_type: :incoming, content_attributes: { 'whatsapp_chat_type' => 'group', 'participant_lid' => 'old@lid' })

    expect { described_class.new(account: account).perform }.to change { message.reload.sender }.from(group_contact).to(participant)
  end

  it 'never resolves a contact from another account' do
    foreign_account = create(:account)
    foreign = create(:contact, account: foreign_account, phone_number: '+5511777777777')
    group_contact.update!(additional_attributes: group_contact.additional_attributes.merge(
      'whatsapp_group_participants' => [{ 'jid' => '5511777777777@c.us', 'contact_id' => foreign.id }]
    ))
    message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: group_contact,
                               message_type: :incoming, content_attributes: { 'whatsapp_chat_type' => 'group', 'whatsapp_participant_jid' => '5511777777777@c.us' })

    result = described_class.new(account: account).perform
    expect(result).to have_attributes(updated: 0, unresolved: 1)
    expect(message.reload.sender).to eq(group_contact)
  end
end
