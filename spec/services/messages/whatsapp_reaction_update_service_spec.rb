require 'rails_helper'

describe Messages::WhatsappReactionUpdateService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) do
    create(:message, account: account, conversation: conversation).tap do |record|
      # The normal message builder intentionally resolves or clears unknown
      # reply references; seed the persisted integration attribute directly.
      record.update_column(:content_attributes, { 'evolution_quoted_message_id' => 'reply-1' })
    end
  end
  let(:base) { { sender_id: 'self', emoji: '❤️', transport: 'evolution', origin: 'platform', event_id: 'reaction-1' } }

  it 'persists a reaction without replacing existing message attributes' do
    described_class.new(message, base).perform

    expect(message.reload.content_attributes).to include('evolution_quoted_message_id' => 'reply-1')
    expect(message.content_attributes['whatsapp_reactions']).to eq([base.stringify_keys])
  end

  it 'replaces a reaction from the same sender and transport' do
    described_class.new(message, base).perform
    described_class.new(message, base.merge(emoji: '😂', event_id: 'reaction-2')).perform

    expect(message.reload.content_attributes['whatsapp_reactions']).to eq([base.merge(emoji: '😂', event_id: 'reaction-2').stringify_keys])
  end

  it 'removes only the matching sender reaction' do
    described_class.new(message, base).perform
    described_class.new(message, base.merge(sender_id: 'contact:5511999999999', emoji: '👍', origin: 'contact')).perform
    described_class.new(message, base.merge(emoji: '')).perform

    expect(message.reload.content_attributes['whatsapp_reactions']).to eq([base.merge(sender_id: 'contact:5511999999999', emoji: '👍', origin: 'contact').stringify_keys])
  end

  it 'keeps a platform reaction as a single item when its Evolution echo arrives' do
    described_class.new(message, base).perform
    described_class.new(message, base.merge(origin: 'mobile', event_id: 'echo-1')).perform

    expect(message.reload.content_attributes['whatsapp_reactions']).to eq([base.merge(event_id: 'echo-1').stringify_keys])
  end
end
