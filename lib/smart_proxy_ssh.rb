require 'smart_proxy_dynflow'

require 'smart_proxy_ssh/version'
require 'smart_proxy_ssh/plugin'

require 'net/ssh'
require 'net/scp'
require 'smart_proxy_ssh/ssh_connector'
require 'smart_proxy_ssh/command'

module Proxy::Ssh

  class << self
    attr_reader :ssh_connector

    def initialize
      @ssh_connector = Proxy::Ssh::SshConnector.spawn('proxy-ssh-connector', Proxy::Dynflow.instance.world)
    end
  end
end


Proxy::Ssh.initialize
