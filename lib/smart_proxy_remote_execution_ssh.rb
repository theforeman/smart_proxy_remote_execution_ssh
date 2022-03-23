require 'smart_proxy_dynflow'
require 'smart_proxy_remote_execution_ssh/version'
require 'smart_proxy_remote_execution_ssh/plugin'
require 'smart_proxy_remote_execution_ssh/webrick_ext'

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

        validate_mode!
        validate_ssh_log_level!
        validate_mqtt_settings!
      end

      def private_key_file
        File.expand_path(Plugin.settings.ssh_identity_key_file)
      end

      def public_key_file
        File.expand_path("#{private_key_file}.pub")
      end

      def validate_mode!
        Plugin.settings.mode = Plugin.settings.mode.to_sym

        unless Plugin::MODES.include? Plugin.settings.mode
          raise "Mode has to be one of #{Plugin::MODES.join(', ')}, given #{Plugin.settings.mode}"
        end

        if Plugin.settings.async_ssh
          Plugin.logger.warn('Option async_ssh is deprecated, use ssh-async mode instead.')

          case Plugin.settings.mode
          when :ssh
            Plugin.logger.warn('Deprecated option async_ssh used together with ssh mode, switching mode to ssh-async.')
            Plugin.settings.mode = :'ssh-async'
          when :'ssh-async'
            # This is a noop
          else
            Plugin.logger.warn('Deprecated option async_ssh used together with incompatible mode, ignoring.')
          end
        end
      end

      def validate_mqtt_settings!
        return unless Plugin.settings.mode == :'pull-mqtt'

        raise 'mqtt_broker has to be set when pull-mqtt mode is used' if Plugin.settings.mqtt_broker.nil?
        raise 'mqtt_port has to be set when pull-mqtt mode is used' if Plugin.settings.mqtt_port.nil?

        if Plugin.settings.mqtt_tls.nil?
          Plugin.settings.mqtt_tls = [:ssl_certificate, :ssl_private_key, :ssl_ca_file].all? { |key| ::Proxy::SETTINGS[key] }
        end
      end

      def validate_ssh_log_level!
        wanted_level = Plugin.settings.ssh_log_level.to_s
        levels = Plugin::SSH_LOG_LEVELS
        unless levels.include? wanted_level
          raise "Wrong value '#{Plugin.settings.ssh_log_level}' for ssh_log_level, must be one of #{levels.join(', ')}"
        end

        current = ::Proxy::SETTINGS.log_level.to_s.downcase

        # regular log levels correspond to upcased ssh logger levels
        ssh, regular = [wanted_level, current].map do |wanted|
          levels.each_with_index.find { |value, _index| value == wanted }.last
        end

        if ssh < regular
          raise 'ssh_log_level cannot be more verbose than regular log level'
        end

        Plugin.settings.ssh_log_level = Plugin.settings.ssh_log_level.to_sym
      end

      def job_storage
        @job_storage ||= Proxy::RemoteExecution::Ssh::JobStorage.new
      end
    end
  end
end
