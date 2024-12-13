require 'mqtt'
require 'json'
require 'time'

module Proxy::RemoteExecution::Ssh::Actions
  class PullScript < Proxy::Dynflow::Action::Runner
    include ::Dynflow::Action::Timeouts

    JobDelivered = Class.new
    PickupTimeout = Class.new

    # The proxy has the job stored in its job storage
    READY_FOR_PICKUP = 'ready_for_pickup'
    # The host was notified over MQTT at least once
    NOTIFIED = 'notified'
    # The host has picked up the job
    DELIVERED = 'delivered'
    # We received at least one output from the host
    RUNNING = 'running'

    execution_plan_hooks.use :cleanup, :on => :stopped

    def plan(action_input)
      super(action_input)
    end

    def run(event = nil)
      if event == JobDelivered
        output[:state] = DELIVERED
        suspend
      elsif event == PickupTimeout
        process_pickup_timeout
      elsif event == ::Dynflow::Action::Timeouts::Timeout
        process_timeout
      elsif event.nil?
        if (timeout = input['execution_timeout_interval'])
          schedule_timeout(timeout, optional: true)
        end
        super
      else
        super
      end
    rescue => e
      cleanup
      action_logger.error(e)
      process_update(Proxy::Dynflow::Runner::Update.encode_exception('Proxy error', e))
    end

    def init_run
      plan_event(PickupTimeout, input[:time_to_pickup], optional: true) if input[:time_to_pickup]

      input[:job_uuid] = 
        job_storage.store_job(host_name, execution_plan_id, run_step_id, input[:script].tr("\r", ''), 
                              effective_user: input[:effective_user])
      output[:state] = READY_FOR_PICKUP
      output[:result] = []

      mqtt_start if with_mqtt?
      suspend
    end

    def cleanup(_plan = nil)
      job_storage.drop_job(execution_plan_id, run_step_id)
      Proxy::RemoteExecution::Ssh::MQTT::Dispatcher.instance.done(input[:job_uuid]) if with_mqtt?
    end

    def process_external_event(event)
      output[:state] = RUNNING
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
      if payload.key?('output')
        Array(payload['output']).each do |line|
          continuous_output.add_output(line, payload['type'])
        end
      end
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
          continuous_output.add_output(update['content'], update['stream'], timestamp: time)
        when 'exit'
          exit_code = update['exit_code'].to_i
        else
          raise "Unexpected update type '#{update['type']}'"
        end
      end

      process_update(Proxy::Dynflow::Runner::Update.new(continuous_output, exit_code))
    end

    def process_timeout
      kill_run "Execution timeout exceeded"
    end

    def kill_run(fail_msg = 'The job was cancelled by the user')
      continuous_output = Proxy::Dynflow::ContinuousOutput.new
      exit_code = nil

      case output[:state]
      when READY_FOR_PICKUP, NOTIFIED
        # If the job is not running yet on the client, wipe it from storage
        cleanup
        exit_code = 'EXCEPTION'
      when DELIVERED, RUNNING
        # Client was notified or is already running, dealing with this situation
        # is only supported if mqtt is available
        # Otherwise we have to wait it out
        if with_mqtt?
          mqtt_cancel 
          fail_msg += ', notifying the host over MQTT'
        else
          fail_msg += ', however the job was triggered without MQTT and cannot be stopped'
        end
      end
      continuous_output.add_output(fail_msg + "\n")
      process_update(Proxy::Dynflow::Runner::Update.new(continuous_output, exit_code))

      suspend unless exit_code
    end

    def mqtt_start
      payload = mqtt_payload_base.merge(
        content: "#{input[:proxy_url]}/ssh/jobs/#{input[:job_uuid]}",
        metadata: {
          'event': 'start',
          'job_uuid': input[:job_uuid],
          'return_url': "#{input[:proxy_url]}/ssh/jobs/#{input[:job_uuid]}/update",
          'version': 'v1',
          'effective_user': input[:effective_user]
        },
      )
      Proxy::RemoteExecution::Ssh::MQTT::Dispatcher.instance.new(input[:job_uuid], mqtt_topic, payload)
      output[:state] = NOTIFIED
    end

    def mqtt_cancel
      payload = mqtt_payload_base.merge(
        content: "#{input[:proxy_url]}/ssh/jobs/#{input[:job_uuid]}/cancel",
        metadata: {
          'event': 'cancel',
          'job_uuid': input[:job_uuid]
        }
      )
      mqtt_notify payload
    end

    def mqtt_notify(payload)
      Proxy::RemoteExecution::Ssh::MQTT.publish(mqtt_topic, JSON.dump(payload))
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

    def job_storage
      Proxy::RemoteExecution::Ssh.job_storage
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

    def process_pickup_timeout
      suspend unless [READY_FOR_PICKUP, NOTIFIED].include? output[:state]

      kill_run 'The job was not picked up in time'
    end

    def with_mqtt?
      ::Proxy::RemoteExecution::Ssh.with_mqtt?
    end
  end
end
