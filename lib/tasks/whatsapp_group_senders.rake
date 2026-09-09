namespace :whatsapp_group_senders do
  desc 'Idempotently backfill real Contact senders for historical WhatsApp group messages (requires ACCOUNT_ID)'
  task backfill: :environment do
    account_id = ENV.fetch('ACCOUNT_ID') { abort 'ACCOUNT_ID is required' }
    account = Account.find(account_id)
    result = Messages::WhatsappGroupSenderBackfillService.new(account: account).perform
    puts "WhatsApp group sender backfill account=#{account.id} scanned=#{result.scanned} updated=#{result.updated} unresolved=#{result.unresolved}"
  end
end
