require 'smart_proxy_dynflow'

require 'smart_proxy_ssh/version'
require 'smart_proxy_ssh/plugin'

require 'smart_proxy_ssh/dispatcher'
require 'smart_proxy_ssh/command_action'

module Proxy::Ssh

  class << self
    attr_reader :dispatcher

    def initialize
      @dispatcher = Proxy::Ssh::Dispatcher.spawn('proxy-ssh-dispatcher',
                                                 :clock  => Proxy::Dynflow.instance.world.clock,
                                                 :logger => Proxy::Dynflow.instance.world.logger)
    end
  end
end


Proxy::Ssh.initialize
