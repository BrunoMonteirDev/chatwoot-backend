class Whatsapp::HybridWahaSessionService
  class Error < StandardError; end
  ACTIONS = %w[status start restart logout qr delete].freeze

  def initialize(channel:)
    @channel = channel
  end

  def create!
    result = client.session(action: :create)
    result.fetch('session')
  end

  def list!
    client.session(action: :list).fetch('sessions')
  end

  def status!(session)
    client.session(action: :status, session: session).fetch('session')
  end

  def action!(action, session)
    raise Error, 'Operação WAHA inválida.' unless ACTIONS.include?(action.to_s)

    client.session(action: action, session: session)
  end

  def bind_connected!(session)
    details = status!(session)
    raise Error, 'A sessão WAHA ainda não está conectada.' unless details['connectionStatus'] == 'connected'
    raise Error, 'A sessão WAHA conectada pertence a outro número. Conecte o mesmo WhatsApp utilizado nesta Inbox oficial.' unless same_phone?(details.dig('me', 'id'))

    Whatsapp::HybridWahaBindingService.new(channel: channel, session: session).bind!
  end

  private

  attr_reader :channel

  def client
    @client ||= Whatsapp::HybridWahaBridgeClient.new(channel: channel)
  end

  def same_phone?(jid)
    waha_phone = normalize(jid)
    official_phone = normalize(channel.phone_number)
    waha_phone.present? && official_phone.present? && waha_phone == official_phone
  end

  def normalize(value)
    value.to_s.sub(/@(c\.us|s\.whatsapp\.net)\z/i, '').gsub(/\D/, '')
  end
end
