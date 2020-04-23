# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'smart_proxy_remote_execution_ssh/version'

Gem::Specification.new do |gem|
  gem.name          = "smart_proxy_remote_execution_ssh"
  gem.version       = Proxy::RemoteExecution::Ssh::VERSION
  gem.authors       = ['Ivan Nečas']
  gem.email         = ['inecas@redhat.com']
  gem.homepage      = "https://github.com/theforeman/smart_proxy_remote_execution_ssh"
  gem.summary       = 'Ssh remote execution provider for Foreman Smart-Proxy'
  gem.description   = <<-EOS
    Ssh remote execution provider for Foreman Smart-Proxy
  EOS

  gem.files            = Dir['lib/smart_proxy_remote_execution_ssh.rb', 'LICENSE', 'README.md',
                             '{lib/smart_proxy_remote_execution_ssh,settings.d}/**/*',
                             'bundler.plugins.d/remote_execution_ssh.rb']
  gem.extra_rdoc_files = ['README.md', 'LICENSE']
  gem.test_files       = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths    = ["lib"]
  gem.license = 'GPL-3.0'

  gem.add_development_dependency "bundler"
  gem.add_development_dependency "rake"
  gem.add_development_dependency('minitest')
  gem.add_development_dependency('mocha', '~> 1')
  gem.add_development_dependency('webmock', '~> 1')
  gem.add_development_dependency('rack-test', '~> 0')
  gem.add_development_dependency('rubocop', '0.32.1')

  gem.add_runtime_dependency('smart_proxy_dynflow', '>= 0.1.0', '< 0.3.0')
  gem.add_runtime_dependency('net-ssh')
end
