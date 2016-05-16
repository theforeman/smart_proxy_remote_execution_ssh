module Proxy::RemoteExecution::Ssh
  class Plugin < Proxy::Plugin
    http_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))
    https_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))

    settings_file "remote_execution_ssh.yml"
    default_settings :ssh_identity_key_file => '~/.ssh/id_rsa_foreman_proxy',
                     :ssh_user              => 'root',
                     :remote_working_dir    => '/var/tmp',
                     :local_working_dir     => '/var/tmp'

    plugin :ssh, Proxy::RemoteExecution::Ssh::VERSION
    after_activation do
      require 'smart_proxy_dynflow'
      require 'smart_proxy_remote_execution_ssh/version'
      require 'smart_proxy_remote_execution_ssh/api'

      begin
        require 'smart_proxy_remote_execution_ssh_core'
      rescue LoadError
      end

      Proxy::RemoteExecution::Ssh.validate!
    end
  end
end
