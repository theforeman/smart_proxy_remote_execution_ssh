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
      job_storage["#{input[:hostname]}-#{execution_plan_id}", run_step_id, 'script.sh'] = input[:script]
      output[:state] = :ready_for_pickup
      mqtt_start if input[:with_mqtt]
      suspend
    end

    def cleanup(_plan = nil)
      job_storage.delete("#{input[:hostname]}-#{execution_plan_id}")
    end

    def process_external_event(event)
      output[:state] = :running
      data = event.data
      continuous_output = Proxy::Dynflow::ContinuousOutput.new
      continuous_output.add_output(lines, 'stdout') if data.key?('output')
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
        if input[:with_mqtt]
          cleanup
          payload = {} # TODO
          mqtt_notify payload
        end
      end
      suspend
    end

    def mqtt_start
      payload = {
        type: 'data',
        message_id: SecureRandom.uuid,
        version: 1,
        sent: DateTime.now.iso8601,
        directive: 'foreman',
        metadata: {
          'return_url': "#{input[:proxy_url]}/job/#{execution_plan_id}/#{run_step_id}/update",
        },
        content: "#{input[:proxy_url]}/job/store/#{execution_plan_id}/#{run_step_id}/script.sh",
      }
      mqtt_notify payload
      output[:state] = :notified
    end

    def mqtt_notify(payload)
      MQTT::Client.connect(settings.mqtt_broker, settings.mqtt_port) do |c|
        c.publish("yggdrasil/#{input[:hostname]}/data/in", JSON.dump(payload), false, 1)
      end
    end

    def settings
      Proxy::Plugin::RemoteExecution::Ssh::Plugin.settings
    end

    def job_storage
      Proxy::RemoteExecution::Ssh.job_storage
    end
  end
end
