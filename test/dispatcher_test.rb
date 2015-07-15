require 'test_helper'
require 'smart_proxy_ssh/dispatcher'

module Proxy::Ssh
  class DispatcherTest < MiniTest::Spec

    let :dispatcher do
      Dispatcher.spawn('ssh-test-dispatcher',
                       :refresh_interval   => 0.01,
                       :clock              => WORLD.clock,
                       :logger             => WORLD.logger,
                       :connector_class    => Support::DummyConnector,
                       :local_working_dir  => "#{DATA_DIR}/server",
                       :remote_working_dir => "#{DATA_DIR}/client")
    end

    let :suspended_action_events do
      []
    end

    let :command do
      Dispatcher::Command.new(:id               => '123',
                              :host             => 'test.example.com',
                              :ssh_user         => 'root',
                              :script           => 'cat /etc/motd',
                              :suspended_action => suspended_action_events)
    end

    let :mocked_async_run_data do
      [Connector::StdoutData.new('Hello world'),
       Connector::StdoutData.new('This is motd'),
       Connector::StatusData.new(0)]
    end

    let :expected_connector_calls do
    end

    before do
      Support::DummyConnector.mocked_async_run_data.concat(mocked_async_run_data)
      dispatcher.tell([:initialize_command, command])
      Support::DummyConnector.wait
    end

    it 'collects the output from command and sends that to suspnded action' do
      suspended_action_events.map do |event|
        { :exit_status => event.exit_status,
          :buffer      => event.buffer.map { |data| [data.class, data.data] } }
      end.must_equal [{ :exit_status => nil, :buffer => [[Connector::StdoutData, 'Hello world']] },
                      { :exit_status => nil, :buffer => [[Connector::StdoutData, 'This is motd']] },
                      { :exit_status => 0,   :buffer => [] }]
    end

    it 'copies the script to the server and runs it there' do
      expected_connector_calls =
          [["root@test.example.com",
            :upload_file,
            "#{DATA_DIR}/server/123/script",
            "#{DATA_DIR}/client/123/script"],
           ["root@test.example.com",
            :async_run,
            "#{DATA_DIR}/client/123/script | /usr/bin/tee #{DATA_DIR}/client/123/output"]]

      Support::DummyConnector.log.must_equal expected_connector_calls
    end

    describe 'using effective user' do
      let :command do
        Dispatcher::Command.new(:id               => '123',
                                :host             => 'test.example.com',
                                :ssh_user         => 'root',
                                :effective_user   => 'guest',
                                :script           => 'cat /etc/motd',
                                :suspended_action => suspended_action_events)
      end

      it 'uses su to set the use to the effecitve one' do
        expected_connector_calls =
            [["root@test.example.com",
              :upload_file,
              "#{DATA_DIR}/server/123/script",
              "#{DATA_DIR}/client/123/script"],
             ["root@test.example.com",
              :async_run,
              "su - guest -c #{DATA_DIR}/client/123/script | /usr/bin/tee #{DATA_DIR}/client/123/output"]]

        Support::DummyConnector.log.must_equal expected_connector_calls
      end
    end

    describe 'killing' do
      it 'uses su to set the use to the effecitve one' do
        Support::DummyConnector.reset
        expected_connector_calls = [["root@test.example.com", :run, "pkill -f #{DATA_DIR}/client/123/script"]]

        dispatcher.ask([:kill, command]).wait
        Support::DummyConnector.log.must_equal expected_connector_calls
      end
    end
  end
end
