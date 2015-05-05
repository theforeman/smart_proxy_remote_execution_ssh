# Smart-proxy Ssh plugin 

This a plugin for foreman smart-proxy allowing using ssh for the
[remote execution](http://theforeman.github.io/foreman_remote_execution/)

## Installation

Add this line to your smart proxy bundler.d/ssh.rb gemfile:

```ruby
gem 'smart_proxy_ssh
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install smart_proxy_ssh

## Usage

To configure this plugin you can use template from settings.d/ssh.yml.example.
You must place ssh.yml config file (based on this template) to your 
smart-proxy config/settings.d/ directory.
