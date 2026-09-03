require 'rails_helper'

describe Whatsapp::HybridWahaBridgeSigner do
  let(:body) { '{"id":1}' }
  let(:request) { instance_double(ActionDispatch::Request, request_method: 'POST', raw_post: body, headers: headers) }
  let(:headers) { described_class.headers(method: 'POST', path: '/internal/x', body: body, request_id: 'request-1') }

  around { |example| ClimateControl.modify HYBRID_WAHA_BRIDGE_SECRET: 'secret' do example.run end }

  it 'accepts only the exact signed method, path and body' do
    expect(described_class.valid?(request, path: '/internal/x')).to be true
    expect(described_class.valid?(request, path: '/internal/other')).to be false
    allow(request).to receive(:raw_post).and_return('{"id":2}')
    expect(described_class.valid?(request, path: '/internal/x')).to be false
  end

  it 'rejects missing, malformed and expired headers' do
    expect(described_class.valid?(instance_double(ActionDispatch::Request, request_method: 'POST', raw_post: body, headers: {}), path: '/internal/x')).to be false
    expired = described_class.headers(method: 'POST', path: '/internal/x', body: body, timestamp: 301.seconds.ago.to_i, request_id: 'old')
    expect(described_class.valid?(instance_double(ActionDispatch::Request, request_method: 'POST', raw_post: body, headers: expired), path: '/internal/x')).to be false
  end
end
