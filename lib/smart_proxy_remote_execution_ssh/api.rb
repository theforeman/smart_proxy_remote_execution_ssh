require 'net/ssh'
require 'base64'
require 'smart_proxy_dynflow/runner'

module Proxy::RemoteExecution
  module Ssh

    class Api < ::Sinatra::Base
      include Sinatra::Authorization::Helpers

      get "/pubkey" do
        File.read(Ssh.public_key_file)
      end

      post "/session" do
        do_authorize_any
        session = Cockpit::Session.new(env)
        unless session.valid?
          return [ 400, "Invalid request: /ssh/session requires connection upgrade to 'raw'" ]
        end
        session.hijack!
        101
      end

      delete '/known_hosts/:name' do |name|
        do_authorize_any
        keys = Net::SSH::KnownHosts.search_for(name)
        return [204] if keys.empty?
        ssh_keys = keys.map { |key| Base64.strict_encode64 key.to_blob }
        Net::SSH::KnownHosts.hostfiles({}, :user)
          .map { |file| File.expand_path file }
          .select { |file| File.readable?(file) && File.writable?(file) }
          .each do |host_file|
            lines = File.foreach(host_file).reject do |line|
              ssh_keys.any? { |key| line.end_with? "#{key}\n" }
            end
            File.open(host_file, 'w') { |f| f.write lines.join }
          end
        204
      end

      # Payload is a hash where
      # exit_code: Integer | NilClass
      # output: String
      post '/job/:task_id/:step_id/update' do |task_id, step_id|
        do_authorize_with_ssl_client

        path = job_path(https_cert_cn, task_id, nil, nil).first
        if Proxy::RemoteExecution::Ssh.job_storage[path].nil?
          status 404
          return ''
        end

        data = MultiJson.load(request.body.read)
        world.event(task_id, step_id, ::Proxy::Dynflow::Runner::ExternalEvent.new(data))
      end

      get "/job/store/:task_id/:step_id/:file" do |task_id, step_id, file|
        do_authorize_with_ssl_client

        path = job_path(https_cert_cn, task_id, step_id.to_i, file)
        content = Proxy::RemoteExecution::Ssh.job_storage[*path]
        if content
          world.event(task_id, step_id.to_i, Proxy::RemoteExecution::Ssh::PullScript::JobDelivered)
          return content
        end

        status 404
        ''
      end

      def job_path(hostname, task_id, step_id, file)
        ["#{hostname}-#{task_id}",
         step_id,
         file,
        ]
      end
    end
  end
end
