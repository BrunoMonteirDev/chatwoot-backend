require 'rails_helper'
require 'thread'

describe ConversationBuilder do
  let(:account) { create(:account) }
  let!(:sms_channel) { create(:channel_sms, account: account) }
  let!(:api_channel) { create(:channel_api, account: account) }
  let!(:sms_inbox) { create(:inbox, channel: sms_channel, account: account) }
  let!(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_sms_inbox) { create(:contact_inbox, contact: contact, inbox: sms_inbox) }
  let(:contact_api_inbox) { create(:contact_inbox, contact: contact, inbox: api_inbox) }

  describe '#perform' do
    it 'creates sms conversation' do
      conversation = described_class.new(
        contact_inbox: contact_sms_inbox,
        params: {}
      ).perform

      expect(conversation.contact_inbox_id).to eq(contact_sms_inbox.id)
    end

    it 'creates api conversation' do
      conversation = described_class.new(
        contact_inbox: contact_api_inbox,
        params: {}
      ).perform

      expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
    end

    it 'reuses the most recent conversation in the same inbox when idempotent' do
      resolved = create(:conversation, contact: contact, contact_inbox: contact_api_inbox, inbox: api_inbox, status: :resolved)

      conversation = described_class.new(contact_inbox: contact_api_inbox, params: { idempotent: true }).perform

      expect(conversation).to eq(resolved)
    end

    context 'when lock_to_single_conversation is true for sms inbox' do
      before do
        sms_inbox.update!(lock_to_single_conversation: true)
      end

      it 'creates sms conversation when existing conversation is not present' do
        conversation = described_class.new(
          contact_inbox: contact_sms_inbox,
          params: {}
        ).perform

        expect(conversation.contact_inbox_id).to eq(contact_sms_inbox.id)
      end

      it 'returns last from existing sms conversations when existing conversation is not present' do
        create(:conversation, contact_inbox: contact_sms_inbox)
        existing_conversation = create(:conversation, contact_inbox: contact_sms_inbox)
        conversation = described_class.new(
          contact_inbox: contact_sms_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end

    context 'when lock_to_single_conversation is true for api inbox' do
      before do
        api_inbox.update!(lock_to_single_conversation: true)
      end

      it 'creates conversation when existing api conversation is not present' do
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
      end

      it 'returns last from existing api conversations when existing conversation is not present' do
        create(:conversation, contact_inbox: contact_api_inbox)
        existing_conversation = create(:conversation, contact_inbox: contact_api_inbox)
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end
  end

  context 'with simultaneous idempotent creations' do
    before(:all) do
      @concurrent_account = create(:account)
      @concurrent_channel = create(:channel_api, account: @concurrent_account)
      @concurrent_inbox = create(:inbox, channel: @concurrent_channel, account: @concurrent_account)
      @concurrent_contact = create(:contact, account: @concurrent_account)
      @concurrent_contact_inbox = create(:contact_inbox, contact: @concurrent_contact, inbox: @concurrent_inbox)
    end

    after(:all) do
      @concurrent_account.destroy!
    end

    it 'creates only one conversation' do
      ready = Queue.new
      start = Queue.new
      results = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            described_class.new(
              contact_inbox: ContactInbox.find(@concurrent_contact_inbox.id),
              params: { idempotent: true }
            ).perform.id
          end
        end
      end

      2.times { ready.pop }
      2.times { start << true }
      conversation_ids = results.map(&:value)

      expect(conversation_ids.uniq.length).to eq(1)
      expect(Conversation.where(contact_id: @concurrent_contact.id, inbox_id: @concurrent_inbox.id).count).to eq(1)
    end
  end
end
