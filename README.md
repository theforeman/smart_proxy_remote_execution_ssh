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

cat > config/settings.d/ssh.yml <<EOF
---
:enabled: true
EOF
```

Install the dependencies

    $ bundle

## Usage

To configure this plugin you can use template from settings.d/ssh.yml.example.
You must place ssh.yml config file (based on this template) to your
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
