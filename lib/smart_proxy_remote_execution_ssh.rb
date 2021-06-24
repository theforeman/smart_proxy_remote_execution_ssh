require 'smart_proxy_dynflow'
require 'smart_proxy_remote_execution_ssh/version'
require 'smart_proxy_remote_execution_ssh/plugin'
require 'smart_proxy_remote_execution_ssh/webrick_ext'

module Proxy::RemoteExecution
  module Ssh
    class << self
      def job_storage
        @job_storage ||= Proxy::RemoteExecution::Ssh::JobStorage.new
      end
    end
  end
end
