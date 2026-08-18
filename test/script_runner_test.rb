# frozen_string_literal: true

require 'test_helper'
require 'smart_proxy_remote_execution_ssh/runners/script_runner'

module Proxy::RemoteExecution::Ssh::Runners
  class ScriptRunnerTest < Minitest::Test
    def build_runner(options = {})
      ScriptRunner.new(
        { hostname: 'somehost.example.com', script: 'echo hello' }.merge(options),
        NoopUserMethod.new
      )
    end

    def remote_working_dir_of(runner)
      runner.instance_variable_get(:@remote_working_dir)
    end

    def stub_setting(value)
      Proxy::RemoteExecution::Ssh::Plugin.settings.stubs(:remote_working_dir).returns(value)
    end

    def test_remote_working_dir_falls_back_to_the_local_setting
      stub_setting('/var/tmp')
      assert_equal '/var/tmp', remote_working_dir_of(build_runner)
    end

    def test_remote_working_dir_prefers_the_value_from_the_options
      stub_setting('/var/tmp')
      assert_equal '/opt/rex', remote_working_dir_of(build_runner(remote_working_dir: '/opt/rex'))
    end

    def test_remote_working_dir_from_the_options_is_shell_escaped
      stub_setting('/var/tmp')
      runner = build_runner(remote_working_dir: '/opt/my rex dir')
      assert_equal '/opt/my\\ rex\\ dir', remote_working_dir_of(runner)
    end

    def test_remote_working_dir_from_the_local_setting_is_shell_escaped
      stub_setting('/opt/my rex dir')
      assert_equal '/opt/my\\ rex\\ dir', remote_working_dir_of(build_runner)
    end

    def test_remote_working_dir_rejects_a_relative_path_from_the_options
      stub_setting('/var/tmp')
      error = assert_raises(RuntimeError) { build_runner(remote_working_dir: 'opt/rex') }
      assert_match(/not an absolute path/, error.message)
    end

    def test_remote_working_dir_rejects_an_empty_path_from_the_options
      stub_setting('/var/tmp')
      assert_raises(RuntimeError) { build_runner(remote_working_dir: '   ') }
    end
  end
end
