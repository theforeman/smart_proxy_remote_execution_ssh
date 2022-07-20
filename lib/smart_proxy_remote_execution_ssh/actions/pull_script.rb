require 'mqtt'
require 'json'
require 'time'

module Proxy::RemoteExecution::Ssh::Actions
  class PullScript < Proxy::Dynflow::Action::Runner
    JobDelivered = Struct.new(:uuid)
    ResendNotification = Class.new

    execution_plan_hooks.use :cleanup, :on => :stopped

    def plan(action_input, mqtt: false)
      super(action_input)
      input[:with_mqtt] = mqtt
    end

    def run(event = nil)
      if event.is_a?(JobDelivered)
        output[:state] = :delivered
        job_storage.mark_as_running(event.uuid)
        suspend
      elsif event == ResendNotification
        if input[:with_mqtt] && %w(ready_for_pickup notified).include?(output[:state])
          schedule_mqtt_resend
          mqtt_start(::Proxy::Dynflow::OtpManager.passwords[execution_plan_id])
        end
        suspend
      else
        super
      end
    end

    def init_run
      otp_password = if input[:with_mqtt]
                       ::Proxy::Dynflow::OtpManager.generate_otp(execution_plan_id)
                     end

      input[:job_uuid] = job_storage.store_job(host_name, execution_plan_id, run_step_id, input[:script].tr("\r", ''))
      output[:state] = :ready_for_pickup
      output[:result] = []
      if input[:with_mqtt]
        schedule_mqtt_resend
        mqtt_start(otp_password)
      end
      suspend
    end

    def cleanup(_plan = nil)
      job_storage.drop_job(execution_plan_id, run_step_id)
      Proxy::Dynflow::OtpManager.passwords.delete(execution_plan_id)
    end

    def process_external_event(event)
      output[:state] = :running
      data = event.data
      case data['version']
      when nil
        process_external_unversioned(data)
      when '1'
        process_external_v1(data)
      else
        raise "Unexpected update message version '#{data['version']}'"
      end
    end

    def process_external_unversioned(payload)
      continuous_output = Proxy::Dynflow::ContinuousOutput.new
      Array(payload['output']).each { |line| continuous_output.add_output(line, payload['type']) } if payload.key?('output')
      exit_code = payload['exit_code'].to_i if payload['exit_code']
      process_update(Proxy::Dynflow::Runner::Update.new(continuous_output, exit_code))
    end

    def process_external_v1(payload)
      continuous_output = Proxy::Dynflow::ContinuousOutput.new
      exit_code = nil

      payload['updates'].each do |update|
        time = Time.parse update['timestamp']
        type = update['type']
        case type
        when 'output'
          continuous_output.add_output(update['content'], update['stream'], time)
        when 'exit'
          exit_code = update['exit_code'].to_i
        else
          raise "Unexpected update type '#{update['type']}'"
        end
      end

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
        mqtt_cancel if input[:with_mqtt]
      end
      suspend
    end

    def mqtt_start(otp_password)
      return unless rate_limit_allowed?

      payload = mqtt_payload_base.merge(
        content: "#{input[:proxy_url]}/ssh/jobs/#{input[:job_uuid]}",
        metadata: {
          'event': 'start',
          'job_uuid': input[:job_uuid],
          'username': execution_plan_id,
          'password': otp_password,
          'return_url': "#{input[:proxy_url]}/ssh/jobs/#{input[:job_uuid]}/update",
        },
      )
      mqtt_notify payload
      output[:state] = :notified
    end

    def mqtt_cancel
      cleanup
      payload = mqtt_payload_base.merge(
        metadata: {
          'event': 'cancel',
          'job_uuid': input[:job_uuid]
        }
      )
      mqtt_notify payload
    end

    def mqtt_notify(payload)
      with_mqtt_client do |c|
        c.publish(mqtt_topic, JSON.dump(payload), false, 1)
      end
    end

    def with_mqtt_client(&block)
      MQTT::Client.connect(settings.mqtt_broker, settings.mqtt_port,
                           :ssl => settings.mqtt_tls,
                           :cert_file => ::Proxy::SETTINGS.foreman_ssl_cert || ::Proxy::SETTINGS.ssl_certificate,
                           :key_file => ::Proxy::SETTINGS.foreman_ssl_key || ::Proxy::SETTINGS.ssl_private_key,
                           :ca_file => ::Proxy::SETTINGS.foreman_ssl_ca || ::Proxy::SETTINGS.ssl_ca_file,
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

    def rate_limit_allowed?
      limit = settings[:pull_rate_limit]
      limit.nil? || limit > job_storage.running_job_count
    end

    def mqtt_payload_base
      {
        type: 'data',
        message_id: SecureRandom.uuid,
        version: 1,
        sent: DateTime.now.iso8601,
        directive: 'foreman'
      }
    end

    def schedule_mqtt_resend
      plan_event(ResendNotification, settings[:mqtt_resend_interval], optional: true)
    end
  end
end
