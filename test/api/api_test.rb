require 'test_helper'

module Proxy::RemoteExecution::Ssh
  class ApiTest < MiniTest::Spec
    include Rack::Test::Methods

    let(:app) { Proxy::RemoteExecution::Ssh::Api.new }

    describe '/pubkey' do
      it 'returns the content of the public key' do
        get '/pubkey'
        last_response.body.must_equal '===public-key==='
      end
    end
  end
end
