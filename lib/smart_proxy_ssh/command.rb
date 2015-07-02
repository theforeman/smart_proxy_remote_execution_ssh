module Proxy::Ssh
  class Command < ::Dynflow::Action

    include Algebrick::Matching

    def run(event = nil)
      match(event,
            on(nil) do
              init_run
            end,
            on(~SshConnector::CommandUpdate) do |update|
              output[:result].concat(update.buffer_to_hash)

              if update.exit_status
                output[:exit_status] = update.exit_status
              else
                suspend
              end
            end)
    end

    def init_run
      output[:result] = []
      suspend do |suspended_action|
        Proxy::Ssh.run_script(input[:id],
                              input[:host],
                              'root',
                              input[:effective_user],
                              input[:script],
                              suspended_action)
      end
    end
  end
end
