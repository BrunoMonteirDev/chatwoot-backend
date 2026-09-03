require 'rails_helper'

describe Whatsapp::EmbeddedSignupService do
  let(:account) { create(:account) }
  let(:params) do
    {
      code: 'test_authorization_code',
      business_id: 'test_business_id',
      waba_id: 'test_waba_id',
      phone_number_id: 'test_phone_number_id'
    }
  end
  let(:service) { described_class.new(account: account, params: params) }
  let(:access_token) { 'test_access_token' }
  let(:phone_info) do
    {
      phone_number_id: params[:phone_number_id],
      phone_number: '+1234567890',
      verified: true,
      business_name: 'Test Business'
    }
  end
  let(:channel) { instance_double(Channel::Whatsapp) }

  describe '#perform' do
    before do
      allow(GlobalConfig).to receive(:clear_cache)

      operational_state_service = instance_double(Whatsapp::OperationalStateService)
      allow(Whatsapp::OperationalStateService).to receive(:new).and_return(operational_state_service)
      allow(operational_state_service).to receive(:update!)

      # Mock service dependencies
      token_exchange = instance_double(Whatsapp::TokenExchangeService)
      allow(Whatsapp::TokenExchangeService).to receive(:new).with(params[:code]).and_return(token_exchange)
      allow(token_exchange).to receive(:perform).and_return(access_token)

      phone_service = instance_double(Whatsapp::PhoneInfoService)
      allow(Whatsapp::PhoneInfoService).to receive(:new)
        .with(params[:waba_id], params[:phone_number_id], access_token).and_return(phone_service)
      allow(phone_service).to receive(:perform).and_return(phone_info)

      channel_creation = instance_double(Whatsapp::ChannelCreationService)
      allow(Whatsapp::ChannelCreationService).to receive(:new)
        .with(account, { waba_id: params[:waba_id], business_name: 'Test Business' }, phone_info, access_token)
        .and_return(channel_creation)
      allow(channel_creation).to receive(:perform).and_return(channel)

      allow(channel).to receive(:setup_webhooks)
      allow(channel).to receive(:phone_number).and_return('+1234567890')
      allow(channel).to receive(:history_eligible?).and_return(false)

      health_service = instance_double(Whatsapp::HealthService)
      allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
      allow(health_service).to receive(:fetch_health_status).and_return({
                                                                          platform_type: 'CLOUD_API',
                                                                          throughput: { 'level' => 'STANDARD' },
                                                                          messaging_limit_tier: 'TIER_1000'
                                                                        })
    end

    it 'creates channel and sets up webhooks' do
      expect(channel).to receive(:setup_webhooks)

      result = service.perform
      expect(result).to eq(channel)
    end

    it 'checks health status after channel creation' do
      health_service = instance_double(Whatsapp::HealthService)
      allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
      expect(health_service).to receive(:fetch_health_status)

      service.perform
    end

    context 'when channel is in pending state' do
      it 'prompts reauthorization for pending channel' do
        health_service = instance_double(Whatsapp::HealthService)
        allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'NOT_APPLICABLE',
                                                                            throughput: { 'level' => 'STANDARD' },
                                                                            messaging_limit_tier: 'TIER_1000'
                                                                          })

        expect(channel).to receive(:prompt_reauthorization!)
        service.perform
      end

      it 'prompts reauthorization when throughput level is NOT_APPLICABLE' do
        health_service = instance_double(Whatsapp::HealthService)
        allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'CLOUD_API',
                                                                            throughput: { 'level' => 'NOT_APPLICABLE' },
                                                                            messaging_limit_tier: 'TIER_1000'
                                                                          })

        expect(channel).to receive(:prompt_reauthorization!)
        service.perform
      end
    end

    context 'when channel is healthy' do
      it 'does not prompt reauthorization for healthy channel' do
        expect(channel).not_to receive(:prompt_reauthorization!)
        service.perform
      end
    end

    context 'when parameters are invalid' do
      it 'raises ArgumentError for missing parameters' do
        invalid_service = described_class.new(account: account, params: { code: '', business_id: '', waba_id: '' })
        expect { invalid_service.perform }.to raise_error(ArgumentError, /Required parameters are missing/)
      end

      it 'rejects an onboarding mode that was not emitted by the official Meta event' do
        invalid_service = described_class.new(account: account, params: params.merge(onboarding_mode: 'guessed'))

        expect { invalid_service.perform }.to raise_error(ArgumentError, 'Invalid onboarding mode')
      end
    end

    context 'when the official event identifies coexistence' do
      let(:coexistence_params) { params.merge(onboarding_mode: 'coexistence') }
      let(:coexistence_service) { described_class.new(account: account, params: coexistence_params) }

      it 'passes the explicit mode to channel creation and webhook setup' do
        token_exchange = instance_double(Whatsapp::TokenExchangeService, perform: access_token)
        allow(Whatsapp::TokenExchangeService).to receive(:new).with(coexistence_params[:code]).and_return(token_exchange)

        phone_service = instance_double(Whatsapp::PhoneInfoService, perform: phone_info)
        allow(Whatsapp::PhoneInfoService).to receive(:new)
          .with(coexistence_params[:waba_id], coexistence_params[:phone_number_id], access_token).and_return(phone_service)

        channel_creation = instance_double(Whatsapp::ChannelCreationService, perform: channel)
        expect(Whatsapp::ChannelCreationService).to receive(:new)
          .with(account, { waba_id: coexistence_params[:waba_id], business_name: 'Test Business' }, phone_info, access_token, onboarding_mode: 'coexistence')
          .and_return(channel_creation)

        expect(channel).to receive(:setup_webhooks)
        coexistence_service.perform
      end
    end

    context 'when service fails' do
      it 'logs and re-raises errors' do
        token_exchange = instance_double(Whatsapp::TokenExchangeService)
        allow(Whatsapp::TokenExchangeService).to receive(:new).and_return(token_exchange)
        allow(token_exchange).to receive(:perform).and_raise('Token error')

        expect(Rails.logger).to receive(:error).with('[WHATSAPP] Embedded signup failed: Token error')
        expect { service.perform }.to raise_error('Token error')
      end

      it 'prompts reauthorization when webhook setup fails' do
        # Create a real channel to test the actual webhook failure behavior
        real_channel = create(:channel_whatsapp, account: account, phone_number: '+1234567890',
                                                 validate_provider_config: false, sync_templates: false)

        # Mock the channel creation to return our real channel
        channel_creation = instance_double(Whatsapp::ChannelCreationService)
        allow(Whatsapp::ChannelCreationService).to receive(:new).and_return(channel_creation)
        allow(channel_creation).to receive(:perform).and_return(real_channel)

        # Mock webhook setup to fail
        allow(real_channel).to receive(:perform_webhook_setup).and_raise('Webhook setup error')

        # Verify channel is not marked for reauthorization initially
        expect(real_channel.reauthorization_required?).to be false

        # The service completes successfully even if webhook fails (webhook error is rescued in setup_webhooks)
        result = service.perform
        expect(result).to eq(real_channel)

        # Verify the channel is now marked for reauthorization
        expect(real_channel.reauthorization_required?).to be true
      end
    end

    context 'with reauthorization flow' do
      let(:inbox_id) { 123 }
      let(:reauth_service) { instance_double(Whatsapp::ReauthorizationService) }
      let(:service_with_inbox) do
        described_class.new(account: account, params: params, inbox_id: inbox_id)
      end

      before do
        allow(Whatsapp::ReauthorizationService).to receive(:new).with(
          account: account,
          inbox_id: inbox_id,
          phone_number_id: params[:phone_number_id],
          waba_id: params[:waba_id]
        ).and_return(reauth_service)
        allow(reauth_service).to receive(:perform).with(access_token, phone_info).and_return(channel)

        allow(channel).to receive(:phone_number).and_return('+1234567890')

        health_service = instance_double(Whatsapp::HealthService)
        allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'CLOUD_API',
                                                                            throughput: { 'level' => 'STANDARD' },
                                                                            messaging_limit_tier: 'TIER_1000'
                                                                          })
      end

      it 'uses ReauthorizationService and sets up webhooks' do
        expect(reauth_service).to receive(:perform)
        expect(channel).to receive(:setup_webhooks)

        result = service_with_inbox.perform
        expect(result).to eq(channel)
      end

      context 'with real channel requiring reauthorization' do
        let(:inbox) { create(:inbox, account: account) }
        let(:whatsapp_channel) do
          create(:channel_whatsapp, account: account, phone_number: '+1234567890',
                                    validate_provider_config: false, sync_templates: false)
        end
        let(:service_with_real_inbox) { described_class.new(account: account, params: params, inbox_id: inbox.id) }

        before do
          inbox.update!(channel: whatsapp_channel)
          whatsapp_channel.prompt_reauthorization!

          setup_reauthorization_mocks
          setup_health_service_mock
        end

        it 'clears reauthorization flag when reauthorization completes' do
          expect(whatsapp_channel.reauthorization_required?).to be true
          result = service_with_real_inbox.perform
          expect(result).to eq(whatsapp_channel)
          expect(whatsapp_channel.reauthorization_required?).to be false
        end

        private

        def setup_reauthorization_mocks
          reauth_service = instance_double(Whatsapp::ReauthorizationService)
          allow(Whatsapp::ReauthorizationService).to receive(:new).with(
            account: account,
            inbox_id: inbox.id,
            phone_number_id: params[:phone_number_id],
            waba_id: params[:waba_id]
          ).and_return(reauth_service)

          allow(reauth_service).to receive(:perform) do
            whatsapp_channel.reauthorized!
            whatsapp_channel
          end

          allow(whatsapp_channel).to receive(:setup_webhooks).and_return(true)
        end

        def setup_health_service_mock
          health_service = instance_double(Whatsapp::HealthService)
          allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
          allow(health_service).to receive(:fetch_health_status).and_return({
                                                                              platform_type: 'CLOUD_API',
                                                                              throughput: { 'level' => 'STANDARD' },
                                                                              messaging_limit_tier: 'TIER_1000'
                                                                            })
        end
      end

      context 'with an existing coexistence channel' do
        let(:inbox) { create(:inbox, account: account) }
        let(:whatsapp_channel) do
          create(
            :channel_whatsapp,
            account: account,
            phone_number: '+1234567890',
            provider: 'whatsapp_cloud',
            validate_provider_config: false,
            sync_templates: false,
            provider_config: {
              'api_key' => 'old-token',
              'phone_number_id' => params[:phone_number_id],
              'business_account_id' => params[:waba_id],
              'source' => 'embedded_signup',
              'onboarding_mode' => 'coexistence'
            }
          )
        end
        let(:coexistence_service) do
          described_class.new(account: account, params: params.merge(onboarding_mode: 'coexistence'), inbox_id: inbox.id)
        end

        before do
          inbox.update!(channel: whatsapp_channel)
          allow(Whatsapp::ReauthorizationService).to receive(:new).and_return(reauth_service)
          allow(reauth_service).to receive(:perform).and_return(whatsapp_channel)
          allow(Channels::Whatsapp::HistorySyncRequestJob).to receive(:perform_later)
        end

        it 'keeps completed History untouched during normal reauthorization' do
          whatsapp_channel.update!(meta_history_status: 'completed', meta_history_completed_at: Time.current)
          allow(whatsapp_channel).to receive(:setup_webhooks).and_return(true)

          coexistence_service.perform

          expect(whatsapp_channel.reload.meta_history_status).to eq('completed')
          expect(Channels::Whatsapp::HistorySyncRequestJob).not_to have_received(:perform_later)
        end

        it 'consumes official offboarding evidence and starts one new History lifecycle' do
          whatsapp_channel.update!(
            meta_connection_status: 'disconnected',
            meta_coexistence_offboarded_at: Time.current,
            meta_history_status: 'completed',
            meta_history_completed_at: Time.current,
            meta_history_subscription_available: true
          )
          allow(whatsapp_channel).to receive(:setup_webhooks).and_return(true)
          expect(Whatsapp::OperationalStateService).to receive(:new).with(whatsapp_channel).and_call_original

          coexistence_service.perform

          expect(whatsapp_channel.reload).to have_attributes(
            meta_connection_status: 'connected',
            meta_coexistence_offboarded_at: nil,
            meta_history_status: 'available'
          )
          expect(Channels::Whatsapp::HistorySyncRequestJob).to have_received(:perform_later).with(whatsapp_channel).once
        end

        it 'preserves evidence, History, and disconnected state when setup fails' do
          whatsapp_channel.update!(
            meta_connection_status: 'disconnected',
            meta_coexistence_offboarded_at: Time.current,
            meta_history_status: 'completed',
            meta_history_completed_at: Time.current,
            meta_history_subscription_available: true
          )
          allow(whatsapp_channel).to receive(:setup_webhooks).and_return(false)
          expect(Whatsapp::OperationalStateService).not_to receive(:new).with(whatsapp_channel)

          coexistence_service.perform

          expect(whatsapp_channel.reload).to have_attributes(
            meta_connection_status: 'disconnected',
            meta_history_status: 'completed'
          )
          expect(whatsapp_channel.meta_coexistence_offboarded_at).to be_present
          expect(Channels::Whatsapp::HistorySyncRequestJob).not_to have_received(:perform_later)
        end
      end
    end
  end
end
