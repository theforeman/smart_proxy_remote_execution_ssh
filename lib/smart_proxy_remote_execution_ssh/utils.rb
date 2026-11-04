require 'open3'

module Proxy::RemoteExecution
  module Utils
    class << self
      def prune_known_hosts!(hostname, port, logger = Logger.new($stdout))
        known_hosts = File.expand_path('~/.ssh/known_hosts')
        return unless File.file?(known_hosts)

        target = if port == 22
                   hostname
                 else
                   "[#{hostname}]:#{port}"
                 end

        _stdout, stderr, status = Open3.capture3('ssh-keygen', '-R', target, '-f', known_hosts)
        logger.warn("Could not remove #{target} from known_hosts: #{stderr.strip}") unless status.success?
      rescue Errno::ENOENT => e
        logger.warn("Could not remove #{target} from known_hosts: #{e}")
      end
    end
  end
end
