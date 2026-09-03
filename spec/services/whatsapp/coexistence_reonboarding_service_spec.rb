require 'rails_helper'

RSpec.describe Whatsapp::CoexistenceReonboardingService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              provider_config: { 'api_key' => 'token', 'phone_number_id' => 'phone', 'business_account_id' => 'waba',
                                                 'source' => 'embedded_signup', 'onboarding_mode' => 'coexistence' })
  end

  before do
    channel.update!(meta_coexistence_offboarded_at: Time.current, meta_history_status: 'completed', meta_history_started_at: 1.hour.ago,
                    meta_history_completed_at: Time.current, meta_history_progress: 100, meta_history_error: 'old error',
                    meta_history_last_chunk: '2:3', meta_history_action_available: false, meta_history_subscription_available: true)
    allow(Channels::Whatsapp::HistorySyncRequestJob).to receive(:perform_later)
  end

  it 'consumes one official offboarding evidence and starts one clean history lifecycle' do
    expect(described_class.new(channel).perform { true }).to be(true)

    expect(channel.reload).to have_attributes(
      meta_coexistence_offboarded_at: nil, meta_history_status: 'available', meta_history_started_at: nil,
      meta_history_completed_at: nil, meta_history_progress: nil, meta_history_error: nil, meta_history_last_chunk: nil,
      meta_history_action_available: false, meta_history_subscription_available: true
    )
    expect(Channels::Whatsapp::HistorySyncRequestJob).to have_received(:perform_later).with(channel).once
  end

  it 'is idempotent when the same FINISH is processed again' do
    described_class.new(channel).perform { true }
    expect(described_class.new(channel.reload).perform { true }).to be(false)

    expect(Channels::Whatsapp::HistorySyncRequestJob).to have_received(:perform_later).with(channel).once
  end

  it 'does not enqueue History when the consuming transaction rolls back' do
    allow(Channels::Whatsapp::HistorySyncRequestJob).to receive(:perform_later).and_call_original
    clear_enqueued_jobs

    ActiveRecord::Base.transaction do
      expect(described_class.new(channel).perform { true }).to be(true)
      expect(enqueued_jobs).to be_empty
      raise ActiveRecord::Rollback
    end

    expect(enqueued_jobs).to be_empty
    expect(channel.reload.meta_coexistence_offboarded_at).to be_present
    expect(channel.meta_history_status).to eq('completed')
  end

  it 'does not consume the evidence when webhook setup fails' do
    expect(described_class.new(channel).perform { false }).to be(false)

    expect(channel.reload.meta_coexistence_offboarded_at).to be_present
    expect(channel.meta_history_status).to eq('completed')
    expect(Channels::Whatsapp::HistorySyncRequestJob).not_to have_received(:perform_later)
  end

  it 'does not start a cycle without official offboarding evidence' do
    channel.update!(meta_coexistence_offboarded_at: nil)

    expect(described_class.new(channel).perform { true }).to be(false)
    expect(Channels::Whatsapp::HistorySyncRequestJob).not_to have_received(:perform_later)
  end

  %w[declined failed].each do |previous_status|
    it "starts a new cycle after #{previous_status} History was officially offboarded" do
      channel.update!(meta_history_status: previous_status, meta_history_completed_at: Time.current)

      expect(described_class.new(channel).perform { true }).to be(true)
      expect(channel.reload.meta_history_status).to eq('available')
      expect(Channels::Whatsapp::HistorySyncRequestJob).to have_received(:perform_later).with(channel).once
    end
  end
end
