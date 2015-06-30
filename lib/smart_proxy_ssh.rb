require 'smart_proxy_dynflow'

require 'smart_proxy_ssh/version'
require 'smart_proxy_ssh/plugin'
require 'smart_proxy_ssh/api'

require 'net/ssh'
require 'smart_proxy_ssh/ssh_connector'
require 'smart_proxy_ssh/command'

module Proxy::Ssh

  class << self
    attr_reader :ssh_connector

    def initialize
      @ssh_connector = Proxy::Ssh::SshConnector.spawn('proxy-ssh-connector', Proxy::Dynflow.instance.world)
    end

    def run_script(id, host, ssh_user, effective_user, script, suspended_action)
      @ssh_connector.tell([:initialize_command, SshConnector::Command[id, host, ssh_user, effective_user, script, suspended_action]])
    end
  end
end


Proxy::Ssh.initialize
