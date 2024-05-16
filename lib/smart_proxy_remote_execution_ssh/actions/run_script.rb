require 'smart_proxy_dynflow/action/shareable'
require 'smart_proxy_dynflow/action/runner'

module Proxy::RemoteExecution::Ssh
  module Actions
    class RunScript < ::Dynflow::Action
      def plan(*args)
        mode = Proxy::RemoteExecution::Ssh::Plugin.settings.mode
        case mode
        when :ssh, :'ssh-async'
          plan_action(ScriptRunner, *args)
        when :pull, :'pull-mqtt'
          plan_action(PullScript, *args)
        end
      end
    end

    class ScriptRunner < Proxy::Dynflow::Action::Runner
      def initiate_runner
        additional_options = {
          :step_id => run_step_id,
          :uuid => execution_plan_id,
        }
        Proxy::RemoteExecution::Ssh::Plugin.runner_class.build(input.merge(additional_options),
                                                               suspended_action: suspended_action)
      end

      def runner_dispatcher
        Dispatcher.instance
      end
    end
  end
end
