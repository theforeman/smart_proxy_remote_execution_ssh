require File.expand_path('test_helper', __dir__)

require 'open3'
require 'rbconfig'

class LoadOrderTest < Minitest::Test
  def test_dynflow_actions_are_available_before_plugin_activation
    lib = File.expand_path('../lib', __dir__)
    script = <<~'RUBY'
      require 'smart_proxy_for_testing'
      require 'smart_proxy_remote_execution_ssh'

      abort 'RunScript is not loaded' unless defined?(Proxy::RemoteExecution::Ssh::Actions::RunScript)
      abort 'ScriptRunner is not loaded' unless defined?(Proxy::RemoteExecution::Ssh::Actions::ScriptRunner)
      abort 'PullScript is not loaded' unless defined?(Proxy::RemoteExecution::Ssh::Actions::PullScript)
    RUBY

    output, status = Open3.capture2e(RbConfig.ruby, "-I#{lib}", '-e', script)

    assert status.success?, output
  end
end
