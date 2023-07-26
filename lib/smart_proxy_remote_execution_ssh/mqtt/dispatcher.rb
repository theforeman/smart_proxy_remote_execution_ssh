require 'concurrent'
require 'mqtt'

class Proxy::RemoteExecution::Ssh::MQTT
  class DispatcherSupervisor < Concurrent::Actor::RestartingContext
    def initialize
      limit = Proxy::RemoteExecution::Ssh::Plugin.settings[:mqtt_rate_limit]
      @dispatcher = DispatcherActor.spawn('MQTT dispatcher',
                                          Proxy::Dynflow::Core.world.clock,
                                          limit)
    end

    def on_message(message)
      case message
      when :dispatcher_reference
        @dispatcher
      when :resumed
        # Carry on
      else
        pass
      end
    end

    # In case an exception is raised during processing, instruct concurrent-ruby
    # to keep going without losing state
    def behaviour_definition
      Concurrent::Actor::Behaviour.restarting_behaviour_definition(:resume!)
    end
  end

  class Dispatcher
    include Singleton

    attr_reader :reference
    def initialize
      @supervisor = DispatcherSupervisor.spawn(name: 'RestartingSupervisor', args: [])
      @reference = @supervisor.ask!(:dispatcher_reference)
    end

    def new(uuid, topic, payload)
      reference.tell([:new, uuid, topic, payload])
    end

    def running(uuid)
      reference.tell([:running, uuid])
    end

    def resend(uuid)
      reference.tell([:resend, uuid])
    end

    def done(uuid)
      reference.tell([:done, uuid])
    end
  end

  class DispatcherActor < Concurrent::Actor::RestartingContext
    JobDefinition = Struct.new :uuid, :topic, :payload

    class Tracker
      def initialize(limit, clock)
        @clock = clock
        @limit = limit
        @jobs = {}
        @pending = []
        @running = Set.new
        @hot = Set.new
        @cold = Set.new
      end

      def new(uuid, topic, payload)
        @jobs[uuid] = JobDefinition.new(uuid, topic, payload)
        @pending << uuid
        dispatch_pending
      end

      def running(uuid)
        [@pending, @hot, @cold].each { |source| source.delete(uuid) }
        @running << uuid
      end

      def resend(uuid)
        return unless @jobs[uuid]

        @pending << uuid
        dispatch_pending
      end

      def done(uuid)
        @jobs.delete(uuid)
        [@pending, @running, @hot, @cold].each do |source|
          source.delete(uuid)
        end
        dispatch_pending
      end

      def needs_processing?
        pending_count.positive? || @hot.any? || @cold.any?
      end

      def pending_count
        pending = @pending.count
        return pending if @limit.nil?

        running = [@running, @hot, @cold].map(&:count).sum
        capacity = @limit - running
        pending > capacity ? capacity : pending
      end

      def dispatch_pending
        pending_count.times do
          mqtt_notify(@pending.first)
          @hot << @pending.shift
        end
      end

      def process
        @cold.each { |uuid| schedule_resend(uuid) }
        @cold = @hot
        @hot = Set.new

        dispatch_pending
      end

      def mqtt_notify(uuid)
        job = @jobs[uuid]
        return if job.nil?

        Proxy::RemoteExecution::Ssh::MQTT.publish(job.topic, JSON.dump(job.payload))
      end

      def settings
        Proxy::RemoteExecution::Ssh::Plugin.settings
      end

      def schedule_resend(uuid)
        @clock.ping(Proxy::RemoteExecution::Ssh::MQTT::Dispatcher.instance, resend_interval, uuid, :resend)
      end

      def resend_interval
        settings[:mqtt_resend_interval]
      end
    end

    def initialize(clock, limit = nil)
      @tracker = Tracker.new(limit, clock)

      interval = Proxy::RemoteExecution::Ssh::Plugin.settings[:mqtt_ttl]
      @timer = Concurrent::TimerTask.new(execution_interval: interval) do
        reference.tell(:tick)
      end
    end

    def on_message(message)
      action, arg = message
      # Enable the timer just in case anything in tracker raises an exception so
      # we can continue
      timer_on
      case action
      when :new
        _, uuid, topic, payload = message
        @tracker.new(uuid, topic, payload)
      when :resend
        @tracker.resend(arg)
      when :running
        @tracker.running(arg)
      when :done
        @tracker.done(arg)
      when :tick
        @tracker.process
      end
      timer_set(@tracker.needs_processing?)
    end

    def timer_set(on)
      on ? timer_on : timer_off
    end

    def timer_on
      @timer.execute
    end

    def timer_off
      @timer.shutdown
    end
  end
end
