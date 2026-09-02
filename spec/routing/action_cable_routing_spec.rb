require 'rails_helper'

RSpec.describe 'ActionCable routing' do
  it 'mounts the websocket endpoint at /cable' do
    paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }

    expect(paths).to include('/cable')
  end
end
