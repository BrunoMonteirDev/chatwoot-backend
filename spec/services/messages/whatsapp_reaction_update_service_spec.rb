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

  it 'accepts add, replace and remove operations from WAHA' do
    waha_reaction = base.merge(transport: 'waha')

    described_class.new(message, waha_reaction).perform
    described_class.new(message, waha_reaction.merge(emoji: '😂', event_id: 'reaction-2')).perform
    described_class.new(message, waha_reaction.merge(emoji: '')).perform

    expect(message.reload.content_attributes['whatsapp_reactions']).to be_empty
  end

  it 'keeps WAHA reactions from multiple authors' do
    waha_reaction = base.merge(transport: 'waha')

    described_class.new(message, waha_reaction).perform
    described_class.new(message, waha_reaction.merge(sender_id: 'contact:5511999999999', emoji: '👍', origin: 'contact')).perform

    expect(message.reload.content_attributes['whatsapp_reactions']).to contain_exactly(
      waha_reaction.stringify_keys,
      waha_reaction.merge(sender_id: 'contact:5511999999999', emoji: '👍', origin: 'contact').stringify_keys
    )
  end

  it 'keeps a WAHA reaction idempotent when its mobile echo arrives' do
    waha_reaction = base.merge(transport: 'waha')

    described_class.new(message, waha_reaction).perform
    described_class.new(message, waha_reaction.merge(origin: 'mobile', event_id: 'echo-1')).perform

    expect(message.reload.content_attributes['whatsapp_reactions']).to eq([waha_reaction.merge(event_id: 'echo-1').stringify_keys])
  end

  it 'accepts the explicit Meta Cloud and Evolution transports' do
    %w[evolution meta_cloud].each do |transport|
      described_class.new(message, base.merge(transport: transport)).perform
    end

    expect(message.reload.content_attributes['whatsapp_reactions']).to contain_exactly(
      base.stringify_keys,
      base.merge(transport: 'meta_cloud').stringify_keys
    )
  end

  it 'rejects an unknown reaction transport' do
    expect do
      described_class.new(message, base.merge(transport: 'unknown')).perform
    end.to raise_error(ArgumentError, 'Invalid WhatsApp reaction')
  end
end
