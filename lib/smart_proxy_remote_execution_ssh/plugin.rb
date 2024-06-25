module Proxy::RemoteExecution::Ssh
  class Plugin < Proxy::Plugin
    SSH_LOG_LEVELS = %w[debug info error fatal].freeze
    MODES = %i[ssh ssh-async pull pull-mqtt].freeze
    # Unix domain socket path length is limited to 104 (on some platforms) characters
    # Socket path is composed of custom path (max 49 characters) + job id (37 characters)
    # + offset(17 characters) + null terminator
    SOCKET_PATH_MAX_LENGTH = 49

    http_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))
    https_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))

    settings_file "remote_execution_ssh.yml"
    default_settings :ssh_identity_key_file   => '~/.ssh/id_rsa_foreman_proxy',
                     :ssh_user                => 'root',
                     :remote_working_dir      => '/var/tmp',
                     :local_working_dir       => '/var/tmp',
                     :socket_working_dir      => '/var/tmp',
                     :kerberos_auth           => false,
                     :cockpit_integration     => true,
                     # When set to nil, makes REX use the runner's default interval
                     # :runner_refresh_interval => nil,
                     :ssh_log_level           => :error,
                     :cleanup_working_dirs    => true,
                     # :mqtt_broker             => nil,
                     # :mqtt_port               => nil,
                     # :mqtt_tls                => nil,
                     # :mqtt_rate_limit         => nil
                     :mode                    => :ssh,
                     :mqtt_resend_interval    => 900,
                     :mqtt_ttl                => 5

    capability(proc { 'cockpit' if settings.cockpit_integration })

    plugin :script, Proxy::RemoteExecution::Ssh::VERSION
    after_activation do
      require 'smart_proxy_dynflow'
      require 'smart_proxy_remote_execution_ssh/version'
      require 'smart_proxy_remote_execution_ssh/cockpit'
      require 'smart_proxy_remote_execution_ssh/api'
      require 'smart_proxy_remote_execution_ssh/actions'
      require 'smart_proxy_remote_execution_ssh/dispatcher'
      require 'smart_proxy_remote_execution_ssh/runners'
      require 'smart_proxy_remote_execution_ssh/utils'
      require 'smart_proxy_remote_execution_ssh/job_storage'

      Proxy::RemoteExecution::Ssh.validate!

      Proxy::Dynflow::TaskLauncherRegistry.register('ssh', Proxy::Dynflow::TaskLauncher::Batch)
      if Proxy::RemoteExecution::Ssh.with_mqtt?
        require 'smart_proxy_remote_execution_ssh/mqtt'
        # Force initialization
        Proxy::RemoteExecution::Ssh::MQTT::Dispatcher.instance
      end
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
