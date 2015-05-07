module Proxy::Ssh
  class Api < ::Sinatra::Base
    helpers ::Proxy::Helpers

    before do
      content_type :json
    end

    post "/command" do
      command = parse_json_body
      Proxy::Ssh.dynflow.world.trigger(Command, command)
    end

  end
end
