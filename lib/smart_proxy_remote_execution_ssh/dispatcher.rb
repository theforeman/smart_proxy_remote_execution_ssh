require 'foreman_tasks_core/runner/dispatcher'

module Proxy::RemoteExecution::Ssh
  class Dispatcher < ::ForemanTasksCore::Runner::Dispatcher
    def refresh_interval
      @refresh_interval ||= Plugin.settings[:runner_refresh_interval] ||
                            Plugin.runner_class::DEFAULT_REFRESH_INTERVAL
    end
  end
end
