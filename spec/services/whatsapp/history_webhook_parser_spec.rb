require 'rails_helper'

describe Whatsapp::HistoryWebhookParser do
  let(:payload) do
    {
      object: 'whatsapp_business_account', entry: [{ id: 'waba-1', changes: [{ field: 'history', value: {
        metadata: { phone_number_id: 'phone-1', display_phone_number: '5511999999999' },
        history: [{ metadata: { phase: 1, chunk_order: 2, progress: 55 }, threads: [{ id: '5511988888888', messages: [{
          id: 'wamid.history-1', from: '5511988888888', to: '5511999999999', timestamp: '1710000001', type: 'text',
          text: { body: 'Histórico' }, context: { id: 'wamid.quoted' }, history_context: { status: 'READ' }
        }] }] }]
      } }] }]
    }
  end

  it 'parses a bounded native chunk without persisting control payloads' do
    event = described_class.new(payload).events.first

    expect(event).to include(kind: 'chunk', phone_number_id: 'phone-1', progress: 55, chunk: '1:2')
    expect(event[:messages]).to contain_exactly(include(source_id: 'wamid.history-1', direction: 'incoming', quoted_message_id: 'wamid.quoted'))
  end

  it 'classifies the documented consent refusal without creating messages' do
    payload[:entry][0][:changes][0][:value].delete(:history)
    payload[:entry][0][:changes][0][:value][:errors] = [{ code: 2_593_109, title: 'Declined' }]

    event = described_class.new(payload).events.first
    expect(event).to include(kind: 'declined', phone_number_id: 'phone-1')
  end

  it 'rejects malformed historical message identities' do
    payload[:entry][0][:changes][0][:value][:history][0][:threads][0][:messages][0][:id] = 'short-id'

    event = described_class.new(payload).events.first
    expect(event).to include(kind: 'progress', messages: [])
  end
end
