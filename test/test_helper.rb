require 'minitest/autorun'
$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')
require "mocha/setup"
require "rack/test"
require 'smart_proxy_for_testing'
require 'support/dummy_connector'

require 'smart_proxy_dynflow'
require 'smart_proxy_dynflow/testing'

WORLD = Proxy::Dynflow::Testing.create_world
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
FileUtils.mkdir_p(logdir) unless File.exist?(logdir)
