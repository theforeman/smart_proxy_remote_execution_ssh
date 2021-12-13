require 'test_helper'
require 'json'
require 'root/root'
require 'root/root_v2_api'
require 'smart_proxy_remote_execution_ssh/plugin'

class SmartProxyRemoteExecutionSshApiFeaturesTest < MiniTest::Test
  include Rack::Test::Methods

  def app
    Proxy::PluginInitializer.new(Proxy::Plugins.instance).initialize_plugins
    Proxy::RootV2Api.new
  end

  def test_features_for_default_mode_without_dynflow
    Proxy::LegacyModuleLoader.any_instance.expects(:load_configuration_file).with('dynflow.yml').returns(enabled: false)
    Proxy::DefaultModuleLoader.any_instance.expects(:load_configuration_file).with('remote_execution_ssh.yml').returns(
      enabled: true,
      ssh_identity_key_file: FAKE_PRIVATE_KEY_FILE,
      mqtt_broker: 'broker.example.com',
      mqtt_port: 1883,
    )

    get '/features'

    response = JSON.parse(last_response.body)

    mod = response['ssh']
    refute_nil(mod)
    assert_equal('failed', mod['state'], Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:ssh])
    assert_equal("Disabling all modules in the group ['ssh'] due to a failure in one of them: 'dynflow' required by 'ssh' could not be found.",
                 Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:ssh])
  end

  def test_features_for_default_mode_with_dynflow
    Proxy::LegacyModuleLoader.any_instance.expects(:load_configuration_file).with('dynflow.yml').returns(enabled: true)
    Proxy::DefaultModuleLoader.any_instance.expects(:load_configuration_file).with('remote_execution_ssh.yml').returns(
      enabled: true,
      ssh_identity_key_file: FAKE_PRIVATE_KEY_FILE,
    )

    get '/features'

    response = JSON.parse(last_response.body)

    mod = response['dynflow']
    refute_nil(mod)
    assert_equal('running', mod['state'], Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:dynflow])

    mod = response['ssh']
    refute_nil(mod)
    assert_equal('running', mod['state'], Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:ssh])
    assert_equal([], mod['capabilities'], 'Has no capabilities')
    assert_equal({}, mod['settings'], 'Has no settings')
  end

  def test_features_for_pull_mqtt_mode_without_required_options
    Proxy::LegacyModuleLoader.any_instance.expects(:load_configuration_file).with('dynflow.yml').returns(enabled: true)
    Proxy::DefaultModuleLoader.any_instance.expects(:load_configuration_file).with('remote_execution_ssh.yml').returns(
      enabled: true,
      ssh_identity_key_file: FAKE_PRIVATE_KEY_FILE,
      mode: 'pull-mqtt',
    )

    get '/features'

    response = JSON.parse(last_response.body)

    mod = response['dynflow']
    refute_nil(mod)
    assert_equal('running', mod['state'], Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:dynflow])

    mod = response['ssh']
    refute_nil(mod)
    assert_equal('failed', mod['state'], Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:ssh])
    assert_equal("Disabling all modules in the group ['ssh'] due to a failure in one of them: Parameter 'mqtt_broker' is expected to have a non-empty value",
                 Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:ssh])
  end

  def test_features_with_dynflow_and_required_options
    Proxy::LegacyModuleLoader.any_instance.expects(:load_configuration_file).with('dynflow.yml').returns(enabled: true)
    Proxy::DefaultModuleLoader.any_instance.expects(:load_configuration_file).with('remote_execution_ssh.yml').returns(
      enabled: true,
      ssh_identity_key_file: FAKE_PRIVATE_KEY_FILE,
      mode: 'pull-mqtt',
      mqtt_broker: 'broker.example.com',
      mqtt_port: 1883,
    )

    get '/features'

    response = JSON.parse(last_response.body)

    mod = response['dynflow']
    refute_nil(mod)
    assert_equal('running', mod['state'], Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:dynflow])

    mod = response['ssh']
    refute_nil(mod)
    assert_equal('running', mod['state'], Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:ssh])
    assert_equal([], mod['capabilities'], 'Has no capabilities')
    assert_equal({}, mod['settings'], 'Has no settings')
  end
end
