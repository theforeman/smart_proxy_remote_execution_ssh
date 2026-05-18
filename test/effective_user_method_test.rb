# frozen_string_literal: true

require 'test_helper'
require 'smart_proxy_remote_execution_ssh/runners/script_runner'

module Proxy::RemoteExecution::Ssh::Runners
  class EffectiveUserMethodTest < Minitest::Test
    WIDE_PASSWORD = "pässw0rd"

    def setup
      super
      @method = SudoUserMethod.new('effective_user', 'ssh_user', WIDE_PASSWORD)
      # Simulate the password having been sent already
      @method.instance_variable_set(:@password_sent, true)
    end

    def test_filter_password_returns_false_for_unrelated_ascii_8bit_data
      data = "\ntouch: cannot touch \xE2\x80\x98/root/test\xE2\x80\x99: Permission denied\n".b
      refute @method.filter_password?(data)
    end

    def test_filter_password_returns_true_for_ascii_8bit_data_containing_wide_password
      data = WIDE_PASSWORD.b
      assert @method.filter_password?(data)
    end

    def test_filter_password_returns_true_when_password_embedded_in_ascii_8bit_data
      data = ("Some output before #{WIDE_PASSWORD} some output after").b
      assert @method.filter_password?(data)
    end

    def test_filter_password_does_not_raise_on_ascii_8bit_data
      data = "\xE2\x80\x98".b
      assert_equal Encoding::ASCII_8BIT, data.encoding
      @method.filter_password?(data) # must not raise
    end
  end
end
