require 'smart_proxy_remote_execution_ssh_core/settings'
require 'smart_proxy_remote_execution_ssh_core/version'
require 'smart_proxy_dynflow_core'
require 'smart_proxy_remote_execution_ssh_core/command_action'
require 'smart_proxy_remote_execution_ssh_core/command_update'
require 'smart_proxy_remote_execution_ssh_core/connector'
require 'smart_proxy_remote_execution_ssh_core/dispatcher'
require 'smart_proxy_remote_execution_ssh_core/session'

module Proxy
  module RemoteExecution
    module Ssh
      class << self
        def initialize
          unless private_key_file
            raise "settings for `ssh_identity_key` not set"
          end

          unless File.exist?(private_key_file)
            raise "Ssh public key file #{private_key_file} doesn't exist.\n"\
              "You can generate one with `ssh-keygen -t rsa -b 4096 -f #{private_key_file} -N ''`"
          end

          unless File.exist?(public_key_file)
            raise "Ssh public key file #{public_key_file} doesn't exist"
          end

          @dispatcher = Proxy::RemoteExecution::Ssh::Dispatcher.spawn('proxy-ssh-dispatcher',
                                                                      :clock  => SmartProxyDynflowCore::Core.instance.world.clock,
                                                                      :logger => SmartProxyDynflowCore::Core.instance.world.logger)
        end

        def dispatcher
          @dispatcher || initialize
        end

        def private_key_file
          File.expand_path(Settings.instance.ssh_identity_key_file)
        end

        def public_key_file
          File.expand_path("#{private_key_file}.pub")
        end
      end
    end
  end
end

SmartProxyDynflowCore::Core.after_initialize { Proxy::RemoteExecution::Ssh.initialize }
