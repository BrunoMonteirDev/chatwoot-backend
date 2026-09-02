require 'rails_helper'

RSpec.describe Whatsapp::OperationalStateService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }

  it 'changes state once and keeps duplicate lifecycle events idempotent' do
    service = described_class.new(channel)
    service.update!(state: 'disconnected', event: 'ACCOUNT_OFFBOARDED', error: 'offboarded')
    changed_at = channel.reload.meta_connection_last_changed_at

    travel 1.minute do
      service.update!(state: 'disconnected', event: 'ACCOUNT_OFFBOARDED', error: 'offboarded')
    end

    expect(channel.reload.meta_connection_last_changed_at).to eq(changed_at)
    expect(channel.meta_account_update_event).to eq('ACCOUNT_OFFBOARDED')
  end

  it 'touches the inbox and emits inbox.updated for realtime consumers' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    with_modified_env ENABLE_INBOX_EVENTS: 'true' do
      described_class.new(channel).update!(state: 'disconnected', event: 'PARTNER_REMOVED')
    end

    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with('inbox.updated', kind_of(Time), inbox: channel.inbox, changed_attributes: kind_of(Object))
  end

  it 'rejects unknown states' do
    expect { described_class.new(channel).update!(state: 'unknown') }.to raise_error(ArgumentError, 'Invalid WhatsApp operational state')
  end
end
