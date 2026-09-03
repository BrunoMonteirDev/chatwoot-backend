require 'rails_helper'

describe Whatsapp::HistoryStateService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', provider_config: { 'api_key' => 'x', 'phone_number_id' => 'phone', 'business_account_id' => 'waba', 'source' => 'embedded_signup', 'onboarding_mode' => 'coexistence' }, sync_templates: false, validate_provider_config: false) }

  it 'keeps progress and chunk monotonic while broadcasting through inbox updates' do
    described_class.new(channel).update!(state: 'syncing', progress: 60, chunk: '2:3')
    described_class.new(channel.reload).update!(state: 'syncing', progress: 40, chunk: '1:9')

    expect(channel.reload).to have_attributes(meta_history_status: 'syncing', meta_history_progress: 60, meta_history_last_chunk: '2:3')
  end

  it 'does not allow undeclared history states' do
    expect { described_class.new(channel).update!(state: 'anything') }.to raise_error(ArgumentError, 'Invalid WhatsApp history state')
  end

  it 'does not regress completed when an earlier chunk is dequeued late' do
    described_class.new(channel).update!(state: 'completed', progress: 100, chunk: '2:4')
    described_class.new(channel.reload).update!(state: 'syncing', progress: 75, chunk: '2:3')

    expect(channel.reload).to have_attributes(meta_history_status: 'completed', meta_history_progress: 100, meta_history_last_chunk: '2:4')
  end

  it 'resets operational state for a new official cycle without changing eligibility rules' do
    described_class.new(channel).update!(state: 'completed', progress: 100, error: 'old', chunk: '2:4')
    described_class.new(channel.reload).reset!(subscription_available: true)

    expect(channel.reload).to have_attributes(meta_history_status: 'available', meta_history_started_at: nil, meta_history_completed_at: nil,
                                              meta_history_progress: nil, meta_history_error: nil, meta_history_last_chunk: nil,
                                              meta_history_action_available: false, meta_history_subscription_available: true)
  end
end
