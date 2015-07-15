require 'smart_proxy_dynflow'

require 'smart_proxy_remote_execution_ssh/version'
require 'smart_proxy_remote_execution_ssh/plugin'

require 'smart_proxy_remote_execution_ssh/dispatcher'
require 'smart_proxy_remote_execution_ssh/command_action'

module Proxy::RemoteExecution
  module Ssh
    class << self
      attr_reader :dispatcher

      def initialize
        @dispatcher = Proxy::RemoteExecution::Ssh::Dispatcher.spawn('proxy-ssh-dispatcher',
                                                   :clock  => Proxy::Dynflow.instance.world.clock,
                                                   :logger => Proxy::Dynflow.instance.world.logger)
      end
    end
  end
end


Proxy::RemoteExecution::Ssh.initialize
