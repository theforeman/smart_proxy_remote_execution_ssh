module Proxy::Ssh
  class Command < ::Dynflow::Action

    include Algebrick::Matching

    include Dynflow::Action::Cancellable

    def run(event = nil)
      match(event,
            on(nil) do
              init_run
            end,
            on(~SshConnector::CommandUpdate) do |update|
              output[:result].concat(update.buffer_to_hash)

              if update.exit_status
                output[:exit_status] = update.exit_status
                error! "Script execution failed" if output[:exit_status] != 0
              else
                suspend
              end
            end,
            on(Dynflow::Action::Cancellable::Cancel) do
              kill_run
            end,
            on(Dynflow::Action::Skip) do
              # do nothing
            end)
    end

    def rescue_strategy
      Dynflow::Action::Rescue::Skip
    end

    def command
      @command ||= SshConnector::Command[input[:id],
                                         input[:host],
                                         'root',
                                         input[:effective_user],
                                         input[:script],
                                         suspended_action]
    end

    def init_run
      output[:result] = []
      Proxy::Ssh.ssh_connector.tell([:initialize_command, command])
      suspend
    end

    def kill_run
      Proxy::Ssh.ssh_connector.tell([:kill, command])
      suspend
    end
  end
end
