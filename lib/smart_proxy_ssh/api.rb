module Proxy::Ssh
  class Api < ::Sinatra::Base
    helpers ::Proxy::Helpers
    helpers ::Proxy::Dynflow::Helpers

    before do
      content_type :json
    end

    post "/command/?" do
      command = parse_json_body
      trigger_task(Command, command).to_json
    end

    post "/command/:task_id/cancel" do |task_id|
      cancel_task(task_id).to_json
    end

  end
end
