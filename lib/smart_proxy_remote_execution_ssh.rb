require 'foreman_tasks_core'
require 'smart_proxy_remote_execution_ssh/version'
require 'smart_proxy_dynflow'
require 'smart_proxy_remote_execution_ssh/webrick_ext'
require 'smart_proxy_remote_execution_ssh/plugin'

module Proxy::RemoteExecution
  module Ssh
    class << self
      def validate!
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

        validate_ssh_log_level!
      end

      def private_key_file
        File.expand_path(Plugin.settings.ssh_identity_key_file)
      end

      def public_key_file
        File.expand_path("#{private_key_file}.pub")
      end

      def validate_ssh_log_level!
        wanted_level = Plugin.settings.ssh_log_level.to_s
        unless Plugin::SSH_LOG_LEVELS.include? wanted_level
          raise "Wrong value '#{Plugin.settings.ssh_log_level}' for ssh_log_level, must be one of #{Plugin::SSH_LOG_LEVELS.join(', ')}"
        end

        current = ::Proxy::SETTINGS.log_level.to_s.downcase

        # regular log levels correspond to upcased ssh logger levels
        ssh, regular = [wanted_level, current].map do |wanted|
          Plugin::SSH_LOG_LEVELS.each_with_index.find { |value, _index| value == wanted }.last
        end

        if ssh < regular
          raise 'ssh_log_level cannot be more verbose than regular log level'
        end

        Plugin.settings.ssh_log_level = Plugin.settings.ssh_log_level.to_sym
      end
    end

    require 'smart_proxy_dynflow_core/task_launcher_registry'
    SmartProxyDynflowCore::TaskLauncherRegistry.register('ssh', ForemanTasksCore::TaskLauncher::Batch)
  end
end
