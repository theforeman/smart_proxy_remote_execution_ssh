module Proxy::Ssh
  class Api < ::Sinatra::Base
    helpers ::Proxy::Helpers

    before do
      content_type :json
    end

    post "/command/?" do
      command = parse_json_body
      triggered = Proxy::Dynflow.world.trigger(Command, command)
      { :task_id => triggered.id }.to_json
    end

  end
end
