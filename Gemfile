source 'https://rubygems.org'
gemspec

group :development do
  gem 'smart_proxy', :git => "https://github.com/theforeman/smart-proxy", :branch => "develop"
  gem 'smart_proxy_dynflow', :git => "https://github.com/theforeman/smart_proxy_dynflow"
  gem 'pry'
end

group :test do
  gem 'public_suffix'
  gem 'rack-test'
end

gem 'sinatra'
gem 'rack', '>= 1.1'

# load local gemfile
local_gemfile = File.join(File.dirname(__FILE__), 'Gemfile.local.rb')
self.instance_eval(Bundler.read_file(local_gemfile)) if File.exist?(local_gemfile)

