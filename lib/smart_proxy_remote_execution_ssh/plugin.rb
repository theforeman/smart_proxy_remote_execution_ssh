require_relative 'validators'

module Proxy::RemoteExecution::Ssh
  class Plugin < Proxy::Plugin
    SSH_LOG_LEVELS = %w[debug info error fatal].freeze
    MODES = %i[ssh async-ssh pull pull-mqtt].freeze

    rackup_path File.expand_path("http_config.ru", __dir__)

    settings_file "remote_execution_ssh.yml"
    default_settings :ssh_identity_key_file   => '~/.ssh/id_rsa_foreman_proxy',
                     :ssh_user                => 'root',
                     :remote_working_dir      => '/var/tmp',
                     :local_working_dir       => '/var/tmp',
                     :kerberos_auth           => false,
                     # When set to nil, makes REX use the runner's default interval
                     # :runner_refresh_interval => nil,
                     :ssh_log_level           => :fatal,
                     :cleanup_working_dirs    => true,
                     # :mqtt_broker             => nil,
                     # :mqtt_port               => nil,
                     :mode                    => :ssh

    load_validators ssh_log_level: Proxy::RemoteExecution::Ssh::Validators::SshLogLevel,
                    rex_ssh_mode: Proxy::RemoteExecution::Ssh::Validators::RexSshMode

    load_programmable_settings do |settings|
      if settings[:ssh_identity_key_file]
        settings[:ssh_identity_key_file] = File.expand_path(settings[:ssh_identity_key_file])
      end

      if settings[:ssh_identity_public_key_file]
        settings[:ssh_identity_public_key_file] = File.expand_path(settings[:ssh_identity_public_key_file])
      elsif settings[:ssh_identity_key_file]
        settings[:ssh_identity_public_key_file] = "#{settings[:ssh_identity_key_file]}.pub"
      end

      if settings[:async_ssh]
        Plugin.logger.warn('Option async_ssh is deprecated, use ssh-async mode instead.')

        case setting_value
        when :ssh
          Plugin.logger.warn('Deprecated option async_ssh used together with ssh mode, switching mode to ssh-async.')
          settings[:mode] = :'ssh-async'
        when :'async-ssh'
          # This is a noop
        else
          Plugin.logger.warn('Deprecated option async_ssh used together with incompatible mode, ignoring.')
        end
      end

      settings[:mode] = settings[:mode].to_sym
      settings[:ssh_log_level] = settings[:ssh_log_level].to_sym
    end

    validate_readable :ssh_identity_key_file, :ssh_identity_public_key_file
    validate :ssh_log_level, ssh_log_level: SSH_LOG_LEVELS
    validate :mode, rex_ssh_mode: MODES
    validate_presence :mqtt_broker, :mqtt_port, if: ->(settings) { settings[:mode] == :'pull-mqtt' }

    plugin :ssh, Proxy::RemoteExecution::Ssh::VERSION

    requires :dynflow, '~> 0.5'

    load_classes do
      require 'smart_proxy_dynflow'
      require 'smart_proxy_dynflow/task_launcher'
      require 'smart_proxy_dynflow/runner'
      require 'smart_proxy_remote_execution_ssh/version'
      require 'smart_proxy_remote_execution_ssh/cockpit'
      require 'smart_proxy_remote_execution_ssh/api'
      require 'smart_proxy_remote_execution_ssh/actions'
      require 'smart_proxy_remote_execution_ssh/dispatcher'
      require 'smart_proxy_remote_execution_ssh/log_filter'
      require 'smart_proxy_remote_execution_ssh/runners'
      require 'smart_proxy_remote_execution_ssh/utils'
      require 'smart_proxy_remote_execution_ssh/job_storage'
    end

    # Not really Smart Proxy dependency injection, but similar enough
    load_dependency_injection_wirings do |container_instance, settings|
      Proxy::Dynflow::TaskLauncherRegistry.register('ssh', Proxy::Dynflow::TaskLauncher::Batch)
    end

    def self.simulate?
      @simulate ||= %w[yes true 1].include? ENV.fetch('REX_SIMULATE', '').downcase
    end

    def self.runner_class
      @runner_class ||= if simulate?
                          Runners::FakeScriptRunner
                        elsif settings.mode == :'ssh-async'
                          Runners::PollingScriptRunner
                        else
                          Runners::ScriptRunner
                        end
    end
  end
end
