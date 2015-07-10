module Proxy::Ssh
  class Command < ::Dynflow::Action

    include Algebrick::Matching

    include Dynflow::Action::Cancellable
    include ::Proxy::Dynflow::Callback::PlanHelper

    def plan(input)
      if callback = input['callback']
        input[:task_id] = callback['task_id']
      else
        input[:task_id] ||= SecureRandom.uuid
      end
      plan_with_callback(input)
    end

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

    def finalize
      # To mark the task as a whole as failed
      error! "Script execution failed" if failed_run?
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
    end

    def failed_run?
      output[:exit_status] != 0
    end
  end
end
