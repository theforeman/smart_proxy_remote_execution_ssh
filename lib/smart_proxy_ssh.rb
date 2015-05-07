require 'pry'

require 'dynflow'

require 'smart_proxy_ssh/version'
require 'smart_proxy_ssh/dynflow'
require 'smart_proxy_ssh/plugin'
require 'smart_proxy_ssh/api'

require 'net/ssh'
require 'smart_proxy_ssh/ssh_connector'
require 'smart_proxy_ssh/command'

module Proxy::Ssh

  class << self
    attr_reader :dynflow, :ssh_connector

    def initialize
      @dynflow = Proxy::Ssh::Dynflow.new
      @ssh_connector = Proxy::Ssh::SshConnector.new(@dynflow.world)
    end
  end
end


Proxy::Ssh.initialize
