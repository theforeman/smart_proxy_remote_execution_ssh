source 'https://rubygems.org'

gemspec :name => 'smart_proxy_remote_execution_ssh_core'

group :development do
  gem 'smart_proxy', :git => "https://github.com/theforeman/smart-proxy", :branch => "develop"
  gem 'smart_proxy_dynflow', :git => "https://github.com/theforeman/smart_proxy_dynflow"
  gem 'pry'
end

if RUBY_VERSION < "2.0"
  gem 'json', '< 2.0.0'
  gem 'net-ssh', '<= 2.10'
  gem 'rest-client', '< 1.7'
  gem 'mime-types', '~> 1.0'
end

# load local gemfile
local_gemfile = File.join(File.dirname(__FILE__), 'Gemfile.local.rb')
self.instance_eval(Bundler.read_file(local_gemfile)) if File.exist?(local_gemfile)

