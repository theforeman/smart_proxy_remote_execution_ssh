require 'smart_proxy_dynflow'

require 'smart_proxy_remote_execution_ssh/version'
require 'smart_proxy_remote_execution_ssh/plugin'

require 'smart_proxy_remote_execution_ssh/connector'
require 'smart_proxy_remote_execution_ssh/command_update'
require 'smart_proxy_remote_execution_ssh/dispatcher'
require 'smart_proxy_remote_execution_ssh/command_action'

require 'smart_proxy_remote_execution_ssh/api'

module Proxy::RemoteExecution
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
                                                                    :clock  => Proxy::Dynflow.instance.world.clock,
                                                                    :logger => Proxy::Dynflow.instance.world.logger)
      end

      def dispatcher
        @dispatcher || initialize
      end

      def private_key_file
        File.expand_path(Ssh::Plugin.settings.ssh_identity_key_file)
      end

      def public_key_file
        File.expand_path("#{private_key_file}.pub")
      end
    end
  end
end

Proxy::Dynflow.after_initialize { Proxy::RemoteExecution::Ssh.initialize }
