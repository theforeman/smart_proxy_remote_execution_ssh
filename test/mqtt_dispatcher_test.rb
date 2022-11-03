require 'test_helper'
require 'smart_proxy_remote_execution_ssh/mqtt'

module Proxy::RemoteExecution::Ssh
  class MQTTDispatcherTest < MiniTest::Spec
    # The tracker dispatches jobs automatically which is what we want when live,
    # but it makes it harder to make assertions about its state. This subclass
    # disables the automatic dispatching and allows us to trigger it by hand,
    class ManualTracker < MQTT::DispatcherActor::Tracker
      def dispatch_pending(manual = false)
        return unless manual

        super()
      end

      attr_reader :pending, :running, :hot, :cold
    end

    describe MQTT::DispatcherActor::Tracker do
      let(:clock) do
        clock = mock()
        clock.stubs(:ping)
      end
      let(:limit) { nil }
      let(:tracker) do
        MQTT::DispatcherActor::Tracker.new(limit, nil)
      end

      describe 'with manual dispatch' do
        let(:tracker) { ManualTracker.new(limit, nil) }

        describe '#pending_count' do
          it 'is 0 when empty' do
            assert_equal tracker.pending_count, 0
          end
        end

        describe 'without limit' do
          it 'does not need processing when empty' do
            refute tracker.needs_processing?
          end

          it 'dispatches new jobs immediately' do
            id = 1
            tracker.new(id, 'topic', {})
            assert_equal tracker.pending_count, 1
            assert tracker.needs_processing?

            tracker.expects(:mqtt_notify).with(id)
            tracker.dispatch_pending(true)
            assert_equal tracker.pending_count, 0
            assert tracker.needs_processing?
          end

          it 'schedules a resend when job moves out of the cold set' do
            tracker.expects(:mqtt_notify)
            tracker.new(1, "topic", {})
            tracker.dispatch_pending(true)
            assert_equal tracker.hot.to_a, [1]
            tracker.process
            assert_equal tracker.cold.to_a, [1]
            tracker.expects(:schedule_resend).with(1)
            tracker.process

            assert_equal tracker.pending, []
            assert tracker.running.empty?
            assert tracker.hot.empty?
            assert tracker.cold.empty?
          end

          it 'needs processing when a job is pending/hot/cold' do
            refute tracker.needs_processing?
            tracker.new(1, "topic", {})
            assert_equal tracker.pending, [1]
            assert tracker.needs_processing?

            # Dispatch it to the hot set
            tracker.expects(:mqtt_notify)
            tracker.dispatch_pending(true)
            assert_equal tracker.hot.to_a, [1]
            assert tracker.needs_processing?

            # Rotate it to the cold set
            tracker.process
            assert_equal tracker.cold.to_a, [1]
            assert tracker.needs_processing?

            # Rotate it out of the cold set into resend
            tracker.expects(:schedule_resend)
            tracker.process
            refute tracker.needs_processing?
            assert_equal tracker.pending, []
            assert tracker.running.empty?
            assert tracker.hot.empty?
            assert tracker.cold.empty?
          end

          it 'does not need processing when a job is waiting for resend' do
            tracker.expects(:mqtt_notify)
            tracker.new(1, "topic", {})
            tracker.dispatch_pending(true)
            assert_equal tracker.hot.to_a, [1]

            tracker.process
            assert_equal tracker.cold.to_a, [1]

            tracker.stubs(:schedule_resend)
            # The job gets rotated out of cold
            tracker.process
            refute tracker.needs_processing?
          end
        end

        describe 'with limit' do
          let(:limit) { 2 }

          it 'dispatches new jobs immediately if possible' do
            tracker.expects(:mqtt_notify).with(1)
            tracker.expects(:mqtt_notify).with(2)
            tracker.new(1, nil, nil)
            tracker.new(2, nil, nil)
            tracker.new(3, nil, nil)

            assert_equal tracker.pending, [1,2,3]
            assert_equal tracker.pending_count, limit

            tracker.dispatch_pending(true)
            assert_equal tracker.pending_count, 0
            assert_equal tracker.pending, [3]
            assert_equal tracker.hot.to_a, [1, 2]
          end

          it 'treats jobs on resend cooldown as not running' do
            tracker.expects(:mqtt_notify).with(1)
            tracker.expects(:mqtt_notify).with(2)
            tracker.new(1, "topic", {})
            tracker.new(2, "topic", {})
            # 1 and are now in hot set
            # This is currently limited
            tracker.new(3, "topic", {})
            tracker.dispatch_pending(true)

            tracker.process
            tracker.dispatch_pending(true)
            # 1 and 2 are now in cold set
            assert tracker.needs_processing?
            # Both slots are taken
            assert_equal tracker.pending_count, 0
            tracker.stubs(:schedule_resend)

            # Both 1 and 2 are considered undelivered so 3 is free to go
            tracker.expects(:mqtt_notify).with(3)
            tracker.process
            tracker.dispatch_pending(true)
          end
        end
      end

      it 'dispatches new jobs immediately if possible' do
        id = 1
        tracker.expects(:mqtt_notify).with(1)
        tracker.new(id, "topic", {})
      end

      it 'resend ignores unknown jobs' do
        tracker.expects(:dispatch_pending).never
        tracker.resend(25)
      end

      describe 'with limit' do
        let(:limit) { 2 }
        let(:tracker) { MQTT::DispatcherActor::Tracker.new(limit, nil) }

        it 'treats running jobs as running' do
          tracker.expects(:mqtt_notify).with(1)
          tracker.expects(:mqtt_notify).with(2)
          tracker.new(1, "topic", {})
          tracker.new(2, "topic", {})
          # 1 and are now in hot set

          # This is currently limited
          tracker.new(3, "topic", {})
          # Rotate 1 and 2 into the cold set
          tracker.process
          tracker.expects(:mqtt_notify).with(3)
          # The call to done unblocks 3 from being executed
          tracker.done(1)
        end
      end
    end
  end
end
