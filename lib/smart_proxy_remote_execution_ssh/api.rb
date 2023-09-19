require 'net/ssh'
require 'base64'
require 'smart_proxy_dynflow/runner'

module Proxy::RemoteExecution
  module Ssh

    class Api < ::Sinatra::Base
      include Sinatra::Authorization::Helpers
      include Proxy::Dynflow::Helpers

      get "/pubkey" do
        File.read(Ssh.public_key_file)
      end

      if Proxy::RemoteExecution::Ssh::Plugin.settings.cockpit_integration
        post "/session" do
          do_authorize_any
          session = Cockpit::Session.new(env)
          unless session.valid?
            return [ 400, "Invalid request: /ssh/session requires connection upgrade to 'raw'" ]
          end
          session.hijack!
          101
        end
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
      post '/jobs/:job_uuid/update' do |job_uuid|
        do_authorize_with_ssl_client

        with_authorized_job(job_uuid) do |job_record|
          data = MultiJson.load(request.body.read)
          notify_job(job_record, ::Proxy::Dynflow::Runner::ExternalEvent.new(data))
        end
      end

      get '/jobs' do
        do_authorize_with_ssl_client

        MultiJson.dump(Proxy::RemoteExecution::Ssh.job_storage.job_uuids_for_host(https_cert_cn))
      end

      get "/jobs/:job_uuid" do |job_uuid|
        do_authorize_with_ssl_client

        with_authorized_job(job_uuid) do |job_record|
          Proxy::RemoteExecution::Ssh::MQTT::Dispatcher.instance.running(job_record[:uuid])
          notify_job(job_record, Actions::PullScript::JobDelivered)
          response.headers['X-Foreman-Effective-User'] = job_record[:effective_user]
          response.headers['X-Foreman-Working-Directory'] = Proxy::RemoteExecution::Ssh::Plugin.settings[:remote_working_dir]
          job_record[:job]
        end
      end

      get "/jobs/:job_uuid/cancel" do |job_uuid|
        do_authorize_with_ssl_client

        with_authorized_job(job_uuid) do |job_record|
          {}
        end
      end

      private

      def notify_job(job_record, event)
        world.event(job_record[:execution_plan_uuid], job_record[:run_step_id], event)
      end

      def with_authorized_job(uuid)
        if (job = authorized_job(uuid))
          yield job
        else
          halt 404
        end
      end

      def authorized_job(uuid)
        job_record = Proxy::RemoteExecution::Ssh.job_storage.find_job(uuid) || {}
        return job_record if authorize_with_token(clear: false, task_id: job_record[:execution_plan_uuid]) ||
                             job_record[:hostname] == https_cert_cn
      end
    end
  end
end
