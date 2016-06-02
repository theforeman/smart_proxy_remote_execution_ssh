require 'minitest/autorun'

ENV['RACK_ENV'] = 'test'

$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')
require "mocha/setup"
require "rack/test"
# require 'smart_proxy_for_testing'
require 'support/dummy_connector'

require 'dynflow'
require 'smart_proxy_dynflow_core'

# DYNFLOW_TESTING_LOG_LEVEL = 0 # for debugging
require 'smart_proxy_dynflow_core/testing'
require 'smart_proxy_remote_execution_ssh_core'
require 'smart_proxy_remote_execution_ssh_core/connector'
require 'smart_proxy_remote_execution_ssh_core/command_update'
require 'smart_proxy_remote_execution_ssh_core/dispatcher'
require 'smart_proxy_remote_execution_ssh_core/command_action'
# require 'smart_proxy_remote_execution_ssh_core/api'

DATA_DIR = File.expand_path('../data', __FILE__)
FAKE_PRIVATE_KEY_FILE = File.join(DATA_DIR, 'fake_id_rsa')
FAKE_PUBLIC_KEY_FILE = "#{FAKE_PRIVATE_KEY_FILE}.pub"

logdir = File.join(File.dirname(__FILE__), '..', 'logs')
FileUtils.mkdir_p(logdir) unless File.exist?(logdir)

def prepare_fake_keys
  Proxy::RemoteExecution::Ssh::Settings.create!(:local_working_dir => DATA_DIR, :ssh_identity_key_file => FAKE_PRIVATE_KEY_FILE)
  FileUtils.mkdir_p(DATA_DIR) unless File.exist?(DATA_DIR)
  File.write(FAKE_PRIVATE_KEY_FILE, '===private-key===')
  File.write(FAKE_PUBLIC_KEY_FILE, '===public-key===')
end

prepare_fake_keys

SmartProxyDynflowCore::Settings.instance.database = nil
SmartProxyDynflowCore::Settings.instance.log_file = nil
SmartProxyDynflowCore::Settings.instance.standalone = true
WORLD = SmartProxyDynflowCore::Dynflow::Testing.create_world
SmartProxyDynflowCore::Core.instance.world = WORLD

class MiniTest::Test
  def setup
    Support::DummyConnector.reset
    prepare_fake_keys
  end

  def teardown
    FileUtils.rm_rf(DATA_DIR) if File.exist?(DATA_DIR)
  end
end
