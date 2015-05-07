module Proxy::Ssh
  class Command < Dynflow::Action

    include Algebrick::Matching

    def run(event = nil)
      match(event,
            on(nil) do
              init_run
            end,
            on(~SshConnector::ProcessUpdate) do |process_update|
              output[:result] << process_update[:lines] unless process_update[:lines].empty?

              if process_update[:exit_status]
                output[:exit_status] = process_update[:exit_status]
              else
                suspend
              end
            end)
    end

    def init_run
      output[:result] = ""
      suspend do |suspended_action|
        SshConnector.instance.run_cmd(cmd, suspended_action)
      end
    end

    def cmd
      input[:cmd]
    end
  end
end
