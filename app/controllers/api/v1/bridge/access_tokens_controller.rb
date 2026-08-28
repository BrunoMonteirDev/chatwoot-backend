# frozen_string_literal: true

class Api::V1::Bridge::AccessTokensController < ApplicationController
  before_action :authenticate_bridge!

  def show
    user = Bridge::ServiceAccount.ensure!
    render json: { api_access_token: user.access_token.token }
  end

  private

  def authenticate_bridge!
    configured_secret = ENV.fetch('BRIDGE_WEBHOOK_SECRET', '')
    supplied_secret = request.headers['X-Bridge-Secret'].to_s
    return if configured_secret.present? && ActiveSupport::SecurityUtils.secure_compare(configured_secret, supplied_secret)

    render json: { error: 'Unauthorized bridge request' }, status: :unauthorized
  end
end
