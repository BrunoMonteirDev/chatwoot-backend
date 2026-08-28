# frozen_string_literal: true

namespace :bridge do
  desc 'Create or repair the private WhatsApp bridge service account'
  task ensure_service_account: :environment do
    user = Bridge::ServiceAccount.ensure!
    Rails.logger.info("[bridge] service account ready: #{user.id}")
  end
end
