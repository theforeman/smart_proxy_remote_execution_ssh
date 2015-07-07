module Proxy::Ssh
  # Service that handles running external commands for Actions::Command
  # Dynflow action. It runs just one (actor) thread for all the commands
  # running in the system and updates the Dynflow actions periodically.
  class SshConnector < ::Dynflow::Actor

    include Algebrick::Matching

    # command comming from action
    Command = Algebrick.type do
      fields!(id: String,
              host: String,
              ssh_user: String,
              effective_user: String,
              script: String,
              suspended_action: Object)
    end

    BufferItem = Algebrick.type do
      fields!(output_type: type { variants(Stdout = atom, Stderr = atom, Status = atom, Error = atom) },
              output:      Object,
              timestamp:   Float)
    end

    # event sent to the action with the update data
    CommandUpdate = Algebrick.type do
      fields!(buffer: Array,
              exit_status: type { variants(NilClass, Integer, String) } )
    end

    module CommandUpdate
      def buffer_to_hash
        self.buffer.map do |buffer_item|
          { output_type: buffer_item.output_type.name.split('::').last,
            output: buffer_item.output,
            timestamp: buffer_item.timestamp }
        end
      end
    end

    def initialize(dynflow_world, logger = dynflow_world.logger)
      @dynflow_world = dynflow_world
      @logger = logger
      @command_buffer = Hash.new { |h, k| h[k] = [] }
      @sessions = {}

      @process_by_output = {}
      @process_buffer = {}
      @refresh_planned = false
    end

    def initialize_command(command)
      @logger.debug("initalizing command [#{command}]")
      session = session(command.host, command.ssh_user)
      remote_script = cp_script_to_remote(session, command)
      output_path = File.join(File.dirname(remote_script), 'output')

      started = false
      session.open_channel do |channel|
        channel.on_data do |ch, data|
          command_buffer(command) << BufferItem[Stdout, data, Time.now.to_f]
        end

        channel.on_extended_data do |ch, type, data|
          command_buffer(command) << BufferItem[Stderr, data, Time.now.to_f]
        end

        channel.on_request("exit-status") do |ch, data|
          status        = data.read_long
          command_buffer(command) << BufferItem[Status, status, Time.now.to_f]
          ch.wait
        end

        channel.on_request("exit-signal") do |ch, data|
          signal = data.read_string
          @logger.debug("exit-signal for [#{command}]: #{signal}")
          command_buffer(command) << BufferItem[Status, signal, Time.now.to_f]
          ch.close
          # wait for the channel to finish so that we know at the end
          # that the session is inactive
          ch.wait
        end

        channel.exec("#{remote_script} 2>&1 | /usr/bin/tee #{ output_path }") do |ch, success|
          started = true
          @logger.debug("command [#{command}] started as script #{ remote_script }")
          unless success
            command_buffer(command).concat([BufferItem[Error, "FAILED: couldn't execute command (ssh.channel.exec)", Time.now.to_f],
                                            BufferItem[Status, 'INIT_ERROR', Time.now.to_f]])
          end
        end
      end
      # iterate on the process call until the script is sent to the host
      session.process(0) until started

      plan_next_refresh
    end

    def refresh
      @logger.debug("refreshing #{@sessions.size} sessions")
      finished_commands = []
      @sessions.values.each { |session| session.process(0) }

      @command_buffer.each do |command, buffer|
        unless buffer.empty?
          status = nil
          buffer.delete_if do |data|
            if data[:output_type] == Status
              status = data[:output]
              true
            end
          end
          @logger.debug("command #{command} got new output: #{buffer.inspect}")
          command.suspended_action << CommandUpdate[buffer, status]
          if status
            @logger.debug("command [#{command}] finished with status #{status}")
            finished_commands << command
          end
          clear_command(command)
        end
      end

      finished_commands.each { |command| finish_command(command) }

      @refresh_planned = false
      plan_next_refresh
    end

    def kill(command)
      @logger.debug("initalizing command [#{command}]")
      ssh = session(command.host, command.ssh_user)
      run_and_wait(ssh, "pkill -f #{ remote_script_file(command) }")
    end

    private

    def session(host, user)
      @logger.debug("opening session to #{user}@#{host}")
      @sessions[[host, user]] ||= Net::SSH.start(host, user)
    end

    def local_script_dir(command)
      File.join('/tmp/foreman-proxy-ssh/server', command[:id])
    end

    def local_script_file(command)
      File.join(local_script_dir(command), 'script')
    end

    def remote_script_dir(command)
      File.join('/tmp/foreman-proxy-ssh/client', command[:id])
    end

    def remote_script_file(command)
      File.join(remote_script_dir(command), 'script')
    end

    def run_and_wait(ssh, command)
      output = ""
      exit_status = nil
      channel = ssh.open_channel do |ch|
        ch.on_data do |data|
          output.concat(data)
        end

        ch.on_extended_data do |_, _, data|
          output.concat(data)
        end

        ch.on_request("exit-status") do |_, data|
          exit_status = data.read_long
        end

        ch.exec command do |_, success|
          raise "could not execute command" unless success
        end
      end
      channel.wait
      return exit_status, output
    end

    def ensure_local_directory(path)
      if File.exists?(path)
        raise "#{ path } expected to be a directory" unless File.directory?(path)
      else
        FileUtils.mkdir_p(path)
      end
      return path
    end

    def ensure_remote_directory(session, path)
      exit_code, output = run_and_wait(session, "mkdir -p #{ path }")
      if exit_code != 0
        raise "Unable to create directory on remote system #{ path }: #{ output }"
      end
    end

    def cp_script_to_remote(session, command)
      local_script_file = write_script_locally(command)
      remote_script_file = File.join(remote_script_dir(command), 'script')
      upload_file(session, local_script_file, remote_script_file)
      return remote_script_file
    end

    def write_script_locally(command)
      path = local_script_file(command)
      ensure_local_directory(File.dirname(path))
      File.write(path, command[:script])
      File.chmod(0777, path)
      return path
    end

    def upload_file(session, local_path, remote_path)
      ensure_remote_directory(session, File.dirname(remote_path))
      scp = Net::SCP.new(session)
      upload_channel = scp.upload(local_path, remote_path)
      upload_channel.wait
    end

    def close_session_if_inactive(host, user)
      if @sessions[[host, user]] && @sessions[[host, user]].channels.empty?
        session = @sessions.delete([host, user])
        session.close unless session.closed?
        @logger.debug("closing session to #{user}@#{host}")
      end
    end

    def command_buffer(command)
      @command_buffer[command]
    end

    def clear_command(command)
      @command_buffer[command] = []
    end

    def finish_command(command)
      @command_buffer.delete(command)
      close_session_if_inactive(command.host, command.ssh_user)
    end

    def refresh_command(command)
      return unless @process_buffer.has_key?(process)
      @process_buffer[process] = ""

      if exit_status
        clear_process(process)
      end
    end

    def plan_next_refresh
      if @sessions.any? && !@refresh_planned
        @logger.debug("planning to refresh")
        @dynflow_world.clock.ping(reference, Time.now + refresh_interval, :refresh)
        @refresh_planned = true
      end
    end

    def refresh_interval
      1
    end
  end
end
