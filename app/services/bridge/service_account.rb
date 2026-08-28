# frozen_string_literal: true

# The WhatsApp bridge needs a durable API identity to process webhooks long
# after an administrator's browser session has expired. Keep that identity in
# Chatwoot itself, and grant it administrator access to every account created
# on this installation. The token is only returned to a container that proves
# knowledge of BRIDGE_WEBHOOK_SECRET; it is never exposed to the dashboard.
module Bridge
  class ServiceAccount
    EMAIL = ENV.fetch('BRIDGE_SERVICE_EMAIL', 'bridge-service@internal.invalid').freeze
    NAME = 'Integração WhatsApp'.freeze

    def self.ensure!
      user = User.find_or_create_by!(email: EMAIL) do |record|
        password = SecureRandom.base58(48)
        record.name = NAME
        record.password = password
        record.password_confirmation = password
        record.confirmed_at = Time.zone.now
        record.custom_attributes = { 'system_account' => 'whatsapp_bridge' }
      end
      Account.find_each { |account| grant_access!(account, user) }
      user.access_token || user.create_access_token
      user
    end

    def self.grant_access!(account, user = ensure!)
      AccountUser.find_or_create_by!(account: account, user: user) do |membership|
        membership.role = :administrator
      end
    end
  end
end
