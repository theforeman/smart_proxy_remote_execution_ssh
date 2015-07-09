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
                finish_run(update)
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
      @command ||= SshConnector::Command[input[:task_id],
                                         input[:hostname],
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

    def finish_run(update)
      output[:exit_status] = update.exit_status
      if input[:task_id] && input[:step_id]
        Proxy::Dynflow::ForemanTasksCallback.send_to_foreman_tasks(input[:task_id], input[:step_id], output)
      end
      error! "Script execution failed" if failed_run?
    end

    def failed_run?
      output[:exit_status] != 0
    end
  end
end
