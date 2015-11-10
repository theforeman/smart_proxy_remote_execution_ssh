[![Build Status](https://img.shields.io/jenkins/s/http/ci.theforeman.org/test_plugin_smart_proxy_remote_execution_ssh_master.svg)](http://ci.theforeman.org/job/test_plugin_smart_proxy_remote_execution_ssh_master)
[![Gem Version](https://img.shields.io/gem/v/smart_proxy_remote_execution_ssh.svg)](https://rubygems.org/gems/smart_proxy_remote_execution_ssh)
[![Code Climate](https://codeclimate.com/github/theforeman/smart_proxy_remote_execution_ssh/badges/gpa.svg)](https://codeclimate.com/github/theforeman/smart_proxy_remote_execution_ssh)
[![GPL License](https://img.shields.io/github/license/theforeman/smart_proxy_remote_execution_ssh.svg)](https://github.com/theforeman/smart_proxy_remote_execution_ssh/blob/master/LICENSE)

# Smart-proxy Ssh plugin 

This a plugin for foreman smart-proxy allowing using ssh for the
[remote execution](http://theforeman.github.io/foreman_remote_execution/)

## Installation

Add this line to your smart proxy bundler.d/ssh.rb gemfile:

```ruby
gem 'smart_proxy_dynflow', :git => 'https://github.com/iNecas/smart_proxy_dynflow.git'
gem 'smart_proxy_ssh', :git => 'https://github.com/iNecas/smart_proxy_ssh.git'
```

Enable the plugins in your smart proxy:

```bash
cat > config/settings.d/dynflow.yml <<EOF
---
:enabled: true
EOF

cat > config/settings.d/remote_execution_ssh.yml <<EOF
---
:enabled: true
EOF
```

Install the dependencies

    $ bundle

## Usage

To configure this plugin you can use template from settings.d/remote_execution_ssh.yml.example.
You must place remote_execution_ssh.yml config file (based on this template) to your
smart-proxy config/settings.d/ directory.

Also, you need to have the `dynflow` plugin enabled to be able to
trigger the tasks.

The simplest thing one can do is just to trigger a command:

```
curl http://my-proxy.example.com:9292/dynflow/tasks \
      -X POST -H 'Content-Type: application/json'\
      -d '{"action_name":  "Proxy::RemoteExecution::Ssh::CommandAction",
           "action_input": {"task_id" : "1234'$RANDOM'",
                            "script": "/usr/bin/ls",
                            "hostname": "localhost",
                            "effective_user": "root"}}'
```
