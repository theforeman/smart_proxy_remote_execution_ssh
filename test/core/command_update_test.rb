# -*- coding: utf-8 -*-
require 'test_helper'

module Proxy::RemoteExecution::Ssh
  class CommandUpdateTest < MiniTest::Spec
    it 'is able to handle encoding' do
      # Simulate output from the connector
      out = '├─2045 /usr/sbin/httpd -DFOREGROUND'.force_encoding('ASCII-8BIT')
      update = CommandUpdate::StdoutData.new(out)
      update.data.must_equal '├─2045 /usr/sbin/httpd -DFOREGROUND'
    end
  end
end
