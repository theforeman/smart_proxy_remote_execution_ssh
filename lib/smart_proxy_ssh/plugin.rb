module Proxy::Ssh
  class Plugin < Proxy::Plugin
    http_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))
    https_rackup_path File.expand_path("http_config.ru", File.expand_path("../", __FILE__))

    settings_file "ssh.yml"
    default_settings :ssh_identity_key => '~/.vagrant.d/insecure_private_key',
        :ssh_user => 'root'
    plugin :ssh, Proxy::Ssh::VERSION
  end
end
