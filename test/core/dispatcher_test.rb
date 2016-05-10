require 'test_helper'

module Proxy::RemoteExecution::Ssh
  class DispatcherTest < MiniTest::Spec
    let :suspended_action_events do
      []
    end

    let :command do
      Dispatcher::Command.new(:id => '123',
                              :host => 'test.example.com',
                              :ssh_user => 'root',
                              :script => 'cat /etc/motd',
                              :suspended_action => suspended_action_events)
    end

    let :dispatcher do
      Dispatcher.spawn('ssh-test-dispatcher',
                       :refresh_interval => 0.01,
                       :clock => WORLD.clock,
                       :logger => WORLD.logger,
                       :connector_class => Support::DummyConnector,
                       :local_working_dir => "#{DATA_DIR}",
                       :remote_working_dir => "#{DATA_DIR}")
    end

    let :mocked_async_run_data do
      [CommandUpdate::StdoutData.new('Hello world'),
       CommandUpdate::StdoutData.new('This is motd'),
       CommandUpdate::StatusData.new(0)]
    end

    before do
      Support::DummyConnector.mocked_async_run_data.concat(mocked_async_run_data)
      dispatcher.tell([:initialize_command, command])
      Support::DummyConnector.wait
    end

    it 'collects the output from command and sends that to suspnded action' do
      suspended_action_events.map do |event|
        { :exit_status => event.exit_status,
          :buffer => event.buffer.map { |data| [data.class, data.data] } }
      end.must_equal [{ :exit_status => nil, :buffer => [[CommandUpdate::StdoutData, 'Hello world']] },
                      { :exit_status => nil, :buffer => [[CommandUpdate::StdoutData, 'This is motd']] },
                      { :exit_status => 0, :buffer => [] }]
    end

    it 'copies the script to the server and runs it there' do
      expected_connector_calls =
          [["root@test.example.com",
            :upload_file,
            "#{DATA_DIR}/foreman-proxy/foreman-ssh-cmd-123/script",
            "#{DATA_DIR}/foreman-ssh-cmd-123/script"],
           ["root@test.example.com",
            :async_run,
            "#{DATA_DIR}/foreman-ssh-cmd-123/script"]]

      Support::DummyConnector.log.must_equal expected_connector_calls
    end

    describe 'using effective user with sudo disabled' do
      let :command do
        Dispatcher::Command.new(:id => '123',
                                :host => 'test.example.com',
                                :ssh_user => 'root',
                                :effective_user => 'guest',
                                :script => 'cat /etc/motd',
                                :suspended_action => suspended_action_events)
      end

      it 'uses su to set the user to the effective one' do
        expected_connector_calls =
            [["root@test.example.com",
              :upload_file,
              "#{DATA_DIR}/foreman-proxy/foreman-ssh-cmd-123/script",
              "#{DATA_DIR}/foreman-ssh-cmd-123/script"],
             ["root@test.example.com",
              :async_run,
              "su - guest -c #{DATA_DIR}/foreman-ssh-cmd-123/script"]]

        Support::DummyConnector.log.must_equal expected_connector_calls
      end
    end

    describe 'using effective user with sudo enabled' do
      let :command do
        Dispatcher::Command.new(:id => '123',
                                :host => 'test.example.com',
                                :ssh_user => 'root',
                                :effective_user => 'guest',
                                :effective_user_method => 'sudo',
                                :script => 'cat /etc/motd',
                                :suspended_action => suspended_action_events)
      end

      it 'uses sudo to set the user to the effective one' do
        expected_connector_calls =
            [["root@test.example.com",
              :upload_file,
              "#{DATA_DIR}/foreman-proxy/foreman-ssh-cmd-123/script",
              "#{DATA_DIR}/foreman-ssh-cmd-123/script"],
             ["root@test.example.com",
              :async_run,
              "sudo -n -u guest #{DATA_DIR}/foreman-ssh-cmd-123/script"]]

        Support::DummyConnector.log.must_equal expected_connector_calls
      end
    end
    describe 'client private key' do
      it 'uses the private key specified in the configuration' do
        connector_options = Support::DummyConnector.last.options
        connector_options[:client_private_key_file].must_equal(Proxy::RemoteExecution::Ssh.private_key_file)
      end
    end

    describe 'host pubilc key' do
      describe 'the public key was provided' do
        let(:command) do
          Dispatcher::Command.new(:id => '123',
                                  :host => 'test.example.com',
                                  :ssh_user => 'root',
                                  :host_public_key => '===host-public-key===',
                                  :effective_user => 'guest',
                                  :script => 'cat /etc/motd',
                                  :suspended_action => suspended_action_events)
        end

        it 'it saves the public key to the known hosts' do
          connector_options = Support::DummyConnector.last.options
          File.read(connector_options[:known_hosts_file]).must_equal "test.example.com ===host-public-key==="
        end
      end

      describe 'the public key was not provided' do
        it "passes the known hosts file, but does'n create it" do
          connector_options = Support::DummyConnector.last.options
          connector_options[:known_hosts_file].wont_be_empty
          refute File.exist?(connector_options[:known_hosts_file])
        end
      end
    end

    describe 'killing' do
      it 'sends pkill to the send signal to the remote process' do
        Support::DummyConnector.reset
        Support::DummyConnector.mocked_async_run_data << CommandUpdate::StdoutData.new('Hello world')
        dispatcher.ask([:initialize_command, command]).wait
        expected_connector_call = ["root@test.example.com", :run, "pkill -f #{DATA_DIR}/foreman-ssh-cmd-123/script"]

        dispatcher.ask([:kill, command]).wait
        Support::DummyConnector.wait
        Support::DummyConnector.log.must_include expected_connector_call
      end
    end
  end
end
