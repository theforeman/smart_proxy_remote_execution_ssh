require 'ostruct'

module Proxy::RemoteExecution::Ssh
  class Settings < OpenStruct

    DEFAULT_SETTINGS = {
      :enabled => true,
      :ssh_identity_key_file => '~/.ssh/id_rsa_foreman_proxy',
      :local_working_dir => '/var/tmp',
      :remote_working_dir => '/var/tmp'
    }

    def initialize(settings = {})
      super(DEFAULT_SETTINGS.merge(settings))
    end

    def load_settings_from_proxy
      DEFAULT_SETTINGS.keys.each do |key|
        self.class.instance[key] = Proxy::RemoteExecution::Ssh::Plugin.settings[key]
      end
    end

    def self.create!(input = {})
      settings = Proxy::RemoteExecution::Ssh::Settings.new input
      self.instance = settings
    end

    def self.instance
      SmartProxyDynflowCore::SETTINGS.plugins['smart_proxy_remote_execution_ssh_core']
    end

    def self.instance=(settings)
      SmartProxyDynflowCore::SETTINGS.plugins['smart_proxy_remote_execution_ssh_core'] = settings
    end
  end
end

Proxy::RemoteExecution::Ssh::Settings.create!
