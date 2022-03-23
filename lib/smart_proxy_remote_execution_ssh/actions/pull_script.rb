require 'mqtt'
require 'json'

module Proxy::RemoteExecution::Ssh::Actions
  class PullScript < Proxy::Dynflow::Action::Runner
    JobDelivered = Class.new

    execution_plan_hooks.use :cleanup, :on => :stopped

    def plan(action_input, mqtt: false)
      super(action_input)
      input[:with_mqtt] = mqtt
    end

    def run(event = nil)
      if event == JobDelivered
        output[:state] = :delivered
        suspend
      else
        super
      end
    end

    def init_run
      otp_password = if input[:with_mqtt]
                       ::Proxy::Dynflow::OtpManager.generate_otp(execution_plan_id)
                     end
      input[:job_uuid] = job_storage.store_job(host_name, execution_plan_id, run_step_id, input[:script])
      output[:state] = :ready_for_pickup
      output[:result] = []
      mqtt_start(otp_password) if input[:with_mqtt]
      suspend
    end

    def cleanup(_plan = nil)
      job_storage.drop_job(execution_plan_id, run_step_id)
      Proxy::Dynflow::OtpManager.passwords.delete(execution_plan_id)
    end

    def process_external_event(event)
      output[:state] = :running
      data = event.data
      continuous_output = Proxy::Dynflow::ContinuousOutput.new
      Array(data['output']).each { |line| continuous_output.add_output(line, 'stdout') } if data.key?('output')
      exit_code = data['exit_code'].to_i if data['exit_code']
      process_update(Proxy::Dynflow::Runner::Update.new(continuous_output, exit_code))
    end

    def kill_run
      case output[:state]
      when :ready_for_pickup
        # If the job is not running yet on the client, wipe it from storage
        cleanup
        # TODO: Stop the action
      when :notified, :running
        # Client was notified or is already running, dealing with this situation
        # is only supported if mqtt is available
        # Otherwise we have to wait it out
        # TODO
        # if input[:with_mqtt]
      end
      suspend
    end

    def mqtt_start(otp_password)
      payload = {
        type: 'data',
        message_id: SecureRandom.uuid,
        version: 1,
        sent: DateTime.now.iso8601,
        directive: 'foreman',
        metadata: {
          'job_uuid': input[:job_uuid],
          'username': execution_plan_id,
          'password': otp_password,
          'return_url': "#{input[:proxy_url]}/ssh/jobs/#{input[:job_uuid]}/update",
        },
        content: "#{input[:proxy_url]}/ssh/jobs/#{input[:job_uuid]}",
      }
      mqtt_notify payload
      output[:state] = :notified
    end

    def mqtt_notify(payload)
      with_mqtt_client do |c|
        c.publish(mqtt_topic, JSON.dump(payload), false, 1)
      end
    end

    def with_mqtt_client(&block)
      MQTT::Client.connect(settings.mqtt_broker, settings.mqtt_port,
                           :ssl => settings.mqtt_tls,
                           :cert_file => ::Proxy::SETTINGS.ssl_certificate,
                           :key_file => ::Proxy::SETTINGS.ssl_private_key,
                           :ca_file => ::Proxy::SETTINGS.ssl_ca_file,
                           &block)
    end

    def host_name
      alternative_names = input.fetch(:alternative_names, {})

      alternative_names[:consumer_uuid] ||
        alternative_names[:fqdn] ||
        input[:hostname]
    end

    def mqtt_topic
      "yggdrasil/#{host_name}/data/in"
    end

    def settings
      Proxy::RemoteExecution::Ssh::Plugin.settings
    end

    def job_storage
      Proxy::RemoteExecution::Ssh.job_storage
    end
  end
end
