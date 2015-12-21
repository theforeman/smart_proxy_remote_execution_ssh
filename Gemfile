source 'https://rubygems.org'

gemspec

if RUBY_VERSION.start_with? '1.9.'
    gem 'net-ssh', '< 3'
else
    gem 'net-ssh'
end

group :development do
  gem 'smart_proxy', :git => "https://github.com/theforeman/smart-proxy", :branch => "develop"
  gem 'smart_proxy_dynflow', :git => "https://github.com/theforeman/smart_proxy_dynflow"
  gem 'pry'
end
