# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'smart_proxy_remote_execution_ssh_core/version'

Gem::Specification.new do |gem|
  gem.name          = "smart_proxy_remote_execution_ssh_core"
  gem.version       = Proxy::RemoteExecution::Ssh::Core::VERSION
  gem.authors       = ['Ivan Nečas']
  gem.email         = ['inecas@redhat.com']
  gem.homepage      = "https://github.com/theforeman/smart_proxy_remote_execution_ssh"
  gem.summary       = 'Ssh remote execution provider for Foreman Smart-Proxy'
  gem.description   = <<-EOS
    Ssh remote execution provider for Foreman Smart-Proxy
  EOS

  gem.files            = Dir['lib/smart_proxy_remote_execution_ssh_core.rb', 'LICENSE', 'README.md',
                             '{bundler.d,lib/smart_proxy_remote_execution_ssh_core,settings.d}/**/*']
  gem.extra_rdoc_files = ['README.md', 'LICENSE']
  gem.test_files       = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths    = ["lib"]
  gem.license = 'GPLv3'

  gem.add_development_dependency "bundler", "~> 1.7"
  gem.add_development_dependency "rake", "~> 10.0"
  gem.add_development_dependency('minitest')
  gem.add_development_dependency('mocha', '~> 1')
  gem.add_development_dependency('webmock', '~> 1')
  gem.add_development_dependency('rack-test', '~> 0')
  gem.add_development_dependency('rubocop', '0.32.1')

  gem.add_runtime_dependency('smart_proxy_dynflow_core', '>= 0.0.7')

  gem.add_runtime_dependency('net-ssh', '<= 2.9.4')
  gem.add_runtime_dependency('net-scp')
end
