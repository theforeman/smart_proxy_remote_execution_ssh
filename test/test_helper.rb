require 'minitest/autorun'

ENV['RACK_ENV'] = 'test'

$LOAD_PATH << File.join(File.dirname(__FILE__), '..', '..', 'lib')
require "mocha/minitest"
require "rack/test"
require 'smart_proxy_for_testing'

require 'smart_proxy_dynflow'

# DYNFLOW_TESTING_LOG_LEVEL = 0 # for debugging
require 'smart_proxy_remote_execution_ssh'
require 'smart_proxy_remote_execution_ssh/api'

DATA_DIR = File.expand_path('../data', __FILE__)
FAKE_PRIVATE_KEY_FILE = File.join(DATA_DIR, 'fake_id_rsa')
FAKE_PUBLIC_KEY_FILE = "#{FAKE_PRIVATE_KEY_FILE}.pub"

logdir = File.join(File.dirname(__FILE__), '..', 'logs')
FileUtils.mkdir_p(logdir) unless File.exist?(logdir)

def prepare_fake_keys
  Proxy::RemoteExecution::Ssh::Plugin.settings.ssh_identity_key_file = FAKE_PRIVATE_KEY_FILE
  # Workaround for Proxy::RemoteExecution::Ssh::Plugin.settings.ssh_identity_key_file returning nil
  Proxy::RemoteExecution::Ssh::Plugin.settings.stubs(:ssh_identity_key_file).returns(FAKE_PRIVATE_KEY_FILE)
  FileUtils.mkdir_p(DATA_DIR) unless File.exist?(DATA_DIR)
  File.write(FAKE_PRIVATE_KEY_FILE, '===private-key===')
  File.write(FAKE_PUBLIC_KEY_FILE, '===public-key===')
end

class Minitest::Test
  def setup
    prepare_fake_keys
  end

  def teardown
    FileUtils.rm_rf(DATA_DIR) if File.exist?(DATA_DIR)
  end
end
