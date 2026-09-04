class Api::V1::Accounts::Conversations::SendCapabilitiesController < Api::V1::Accounts::Conversations::BaseController
  def show
    render json: Whatsapp::SendCapabilityService.new(@conversation).perform
  end
end
