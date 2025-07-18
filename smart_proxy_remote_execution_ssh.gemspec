lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'smart_proxy_remote_execution_ssh/version'

Gem::Specification.new do |gem|
  gem.name          = "smart_proxy_remote_execution_ssh"
  gem.version       = Proxy::RemoteExecution::Ssh::VERSION
  gem.authors       = ['Ivan Nečas']
  gem.email         = ['inecas@redhat.com']
  gem.homepage      = "https://github.com/theforeman/smart_proxy_remote_execution_ssh"
  gem.summary       = 'Ssh remote execution provider for Foreman Smart-Proxy'
  gem.description   = <<-DESCRIPTION
    Ssh remote execution provider for Foreman Smart-Proxy
  DESCRIPTION

  gem.files            = Dir['lib/smart_proxy_remote_execution_ssh.rb', 'LICENSE', 'README.md',
                             '{lib/smart_proxy_remote_execution_ssh,settings.d}/**/*',
                             'bundler.d/remote_execution_ssh.rb']
  gem.extra_rdoc_files = ['README.md', 'LICENSE']
  gem.test_files       = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths    = ["lib"]
  gem.license = 'GPL-3.0-only'

  gem.required_ruby_version = '>= 2.7.0'

  gem.add_development_dependency("rake", '~> 13.0')
  gem.add_development_dependency('minitest', '~> 5.23')
  gem.add_development_dependency('mocha', '~> 2.0')
  gem.add_development_dependency('webmock', '~> 1')
  gem.add_development_dependency('rack-test', '~> 0')
  gem.add_development_dependency('rubocop', '~> 0.82.0')

  gem.add_runtime_dependency('ed25519', '>= 1.2', '< 2.0')
  gem.add_runtime_dependency('bcrypt_pbkdf', '>= 1.0', '< 2.0')
  gem.add_runtime_dependency('smart_proxy_dynflow', '~> 0.9', '>= 0.9.4')
  gem.add_runtime_dependency('net-ssh', '~> 7.2')
  gem.add_runtime_dependency('mqtt', '~> 0.5')
end
