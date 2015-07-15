require 'minitest/autorun'
$: << File.join(File.dirname(__FILE__), '..', 'lib')
require "mocha/setup"
require "rack/test"
require 'smart_proxy_for_testing'
require 'support/dummy_connector'

require 'smart_proxy_dynflow'

require 'dynflow/testing'

Concurrent.disable_at_exit_handlers!
WORLD = Proxy::Dynflow.instance.create_world do |config|
  config.exit_on_terminate = false
  config.auto_terminate    = false
  config.logger_adapter    = Dynflow::LoggerAdapters::Simple.new $stderr, 4
end

DATA_DIR = File.expand_path('../data', __FILE__)

class MiniTest::Test
  def setup
    Support::DummyConnector.reset
  end

  def teardown
    FileUtils.rm_rf(DATA_DIR) if File.exist?(DATA_DIR)
  end
end


logdir = File.join(File.dirname(__FILE__), '..', 'logs')
FileUtils.mkdir_p(logdir) unless File.exists?(logdir)
