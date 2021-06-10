require 'smart_proxy_dynflow/runner/dispatcher'

module Proxy::RemoteExecution::Ssh
  class Dispatcher < ::Proxy::Dynflow::Runner::Dispatcher
    def refresh_interval
      @refresh_interval ||= Plugin.settings[:runner_refresh_interval] ||
                            Plugin.runner_class::DEFAULT_REFRESH_INTERVAL
    end
  end
end
