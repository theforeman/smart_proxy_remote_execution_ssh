module Proxy::Ssh
  class Api < ::Sinatra::Base
    helpers ::Proxy::Helpers

    before do
      content_type :json
    end

    get "/hello" do
      logger.debug "hello from ssh plugin"
      "Hello from ssh plugin"
    end

  end
end
