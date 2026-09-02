require 'rails_helper'

RSpec.describe Channels::Whatsapp::HistoryChunkImportJob do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: channel.account, phone_number: '+5511988888888') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: channel.inbox, contact: contact,
                          contact_inbox: create(:contact_inbox, contact: contact, inbox: channel.inbox))
  end
  let(:event) do
    {
      kind: 'chunk', phone_number_id: 'phone-1', progress: 100, chunk: '1:1',
      messages: [{ source_id: 'wamid.history-realtime-race', transport: 'meta_cloud', native_meta: true, direction: 'incoming',
                   timestamp: 1_710_000_001, content: 'History duplicate', thread_id: '5511988888888', remote_jid: '5511988888888' }]
    }
  end

  before do
    channel.update!(provider_config: channel.provider_config.merge('api_key' => 'token', 'phone_number_id' => 'phone-1',
                                                                    'business_account_id' => 'waba-1', 'source' => 'embedded_signup',
                                                                    'onboarding_mode' => 'coexistence'))
  end

  it 'reuses the realtime message conversation and does not create a duplicate' do
    existing = create(:message, account: channel.account, inbox: channel.inbox, conversation: conversation,
                               source_id: 'wamid.history-realtime-race', content: 'Realtime message')
    job = described_class.new
    allow(job).to receive(:with_lock).and_yield

    expect { job.perform(channel, event) }.not_to change(Message, :count)
    expect(Conversation.where(inbox: channel.inbox).count).to eq(1)
    expect(existing.reload.content).to eq('Realtime message')
    expect(channel.reload).to have_attributes(meta_history_status: 'completed', meta_history_progress: 100)
  end

  it 'uses an inbox-and-phone scoped lock' do
    job = described_class.new
    key = "whatsapp:history:#{channel.account_id}:#{channel.id}:phone-1"

    expect(job).to receive(:with_lock).with(key, 60.seconds).and_yield
    job.perform(channel, event.merge(messages: []))
  end
end
