# -*- coding: utf-8 -*-
require 'test_helper'

module Proxy::RemoteExecution::Ssh
  class ConnectorTest < MiniTest::Spec
    let :connector do
      Support::DummyConnector.new('test.example.com', 'root')
    end

    it 'is able to handle encoding' do
      # Simulate output from the connector
      out = '├─2045 /usr/sbin/httpd -DFOREGROUND'.force_encoding('ASCII-8BIT')
      new_out = connector.send(:handle_encoding, out)
      new_out.must_equal '├─2045 /usr/sbin/httpd -DFOREGROUND'
    end
  end
end
