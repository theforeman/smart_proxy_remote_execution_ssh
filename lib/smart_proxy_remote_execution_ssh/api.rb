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

      get "/ca_pubkey" do
        if Ssh.ca_public_key_file
          File.read(Ssh.ca_public_key_file)
        end
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

      # Payload is a hash where
      # exit_code: Integer | NilClass
      # output: any, depends on the action consuming the data
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
          if Proxy::RemoteExecution::Ssh.with_mqtt?
            Proxy::RemoteExecution::Ssh::MQTT::Dispatcher.instance.running(job_record[:uuid])
          end
          notify_job(job_record, Actions::PullScript::JobDelivered)
          response.headers['X-Foreman-Effective-User'] = job_record[:effective_user] if job_record[:effective_user]
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
        Proxy::RemoteExecution::Ssh.job_storage.find_job(uuid, https_cert_cn)
      end
    end
  end
end
