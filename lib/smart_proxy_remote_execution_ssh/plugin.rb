module Proxy::RemoteExecution::Ssh
  class Plugin < Proxy::Plugin
    SSH_LOG_LEVELS = %w[debug info warn error fatal].freeze

    http_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))
    https_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))

    settings_file "remote_execution_ssh.yml"
    default_settings :ssh_identity_key_file   => '~/.ssh/id_rsa_foreman_proxy',
                     :ssh_user                => 'root',
                     :remote_working_dir      => '/var/tmp',
                     :local_working_dir       => '/var/tmp',
                     :kerberos_auth           => false,
                     :async_ssh               => false,
                     # When set to nil, makes REX use the runner's default interval
                     # :runner_refresh_interval => nil,
                     :ssh_log_level           => :fatal,
                     :cleanup_working_dirs    => true

    plugin :ssh, Proxy::RemoteExecution::Ssh::VERSION
    after_activation do
      require 'smart_proxy_dynflow'
      require 'smart_proxy_remote_execution_ssh/version'
      require 'smart_proxy_remote_execution_ssh/cockpit'
      require 'smart_proxy_remote_execution_ssh/api'
      require 'smart_proxy_remote_execution_ssh/actions/run_script'
      require 'smart_proxy_remote_execution_ssh/actions/pull_script'
      require 'smart_proxy_remote_execution_ssh/dispatcher'
      require 'smart_proxy_remote_execution_ssh/log_filter'
      require 'smart_proxy_remote_execution_ssh/runners'
      require 'smart_proxy_remote_execution_ssh/utils'

      Proxy::RemoteExecution::Ssh.validate!

      Proxy::Dynflow::TaskLauncherRegistry.register('ssh', Proxy::Dynflow::TaskLauncher::Batch)
    end

    def self.simulate?
      @simulate ||= %w[yes true 1].include? ENV.fetch('REX_SIMULATE', '').downcase
    end

    def self.runner_class
      @runner_class ||= if simulate?
                          Runners::FakeScriptRunner
                        elsif settings[:async_ssh]
                          Runners::PollingScriptRunner
                        else
                          Runners::ScriptRunner
                        end
    end
  end
end
