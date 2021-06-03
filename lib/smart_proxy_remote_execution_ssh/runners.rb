module Proxy::RemoteExecution::Ssh
  module Runners
    require 'smart_proxy_remote_execution_ssh/runners/script_runner'
    require 'smart_proxy_remote_execution_ssh/runners/polling_script_runner'
    require 'smart_proxy_remote_execution_ssh/runners/fake_script_runner'
  end
end
