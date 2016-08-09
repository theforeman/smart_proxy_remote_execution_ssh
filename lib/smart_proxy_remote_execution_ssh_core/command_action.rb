module Proxy
  module RemoteExecution
    module Ssh
      class CommandAction < ::Dynflow::Action
        include ::Dynflow::Action::Cancellable
        include ::SmartProxyDynflowCore::Callback::PlanHelper

        def plan(input)
          if callback = input['callback']
            input[:task_id] = callback['task_id']
          else
            input[:task_id] ||= SecureRandom.uuid
          end
          plan_with_callback(input)
        end

        def run(event = nil)
          case event
          when nil
            init_run
          when CommandUpdate
            process_update(event)
          when ::Dynflow::Action::Cancellable::Cancel
            kill_run
          when ::Dynflow::Action::Skip
            # do nothing
          else
            raise "Unexpected event #{event.inspect}"
          end
        rescue => e
          action_logger.error(e)
          process_update(CommandUpdate.new(CommandUpdate.encode_exception("Proxy error", e)))
        end

        def finalize
          # To mark the task as a whole as failed
          error! "Script execution failed" if failed_run?
        end

        def rescue_strategy_for_self
          ::Dynflow::Action::Rescue::Skip
        end

        def command
          @command ||= Dispatcher::Command.new(:id                    => input[:task_id],
                                               :host                  => input[:hostname],
                                               :ssh_user              => input[:ssh_user] || 'root',
                                               :effective_user        => input[:effective_user],
                                               :script                => input[:script],
                                               :effective_user_method => input[:effective_user_method],
                                               :host_public_key       => input[:host_public_key],
                                               :verify_host           => input[:verify_host],
                                               :suspended_action      => suspended_action)
        end

        def init_run
          output[:result] = []
          Proxy::RemoteExecution::Ssh.dispatcher.tell([:initialize_command, command])
          suspend
        end

        def kill_run
          Proxy::RemoteExecution::Ssh.dispatcher.tell([:kill, command])
          suspend
        end

        def finish_run(update)
          output[:exit_status] = update.exit_status
        end

        def process_update(update)
          output[:result].concat(update.buffer_to_hash)
          if update.exit_status
            finish_run(update)
          else
            suspend
          end
        end

        def failed_run?
          output[:exit_status] != 0
        end
      end
    end
  end
end
