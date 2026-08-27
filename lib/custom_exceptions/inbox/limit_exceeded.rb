# frozen_string_literal: true

class CustomExceptions::Inbox::LimitExceeded < CustomExceptions::Base
  def message
    'Limite de caixas de entrada desta conta atingido. Fale com o suporte para ampliar o limite.'
  end

  def to_hash
    { error: message }
  end

  def http_status
    :payment_required
  end
end
