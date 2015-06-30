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

    # event sent to the action with the update data
    CommandUpdate = Algebrick.type do
      fields!(output:       Array,
              exit_status: type { variants(NilClass, Integer) } )
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
      started = false
      session.open_channel do |channel|
        channel.on_data do |ch, data|
          command_buffer(command) << [:stdout, data]
        end

        channel.on_extended_data do |ch, type, data|
          command_buffer(command) << [:stderr, data]
        end

        channel.on_request("exit-status") do |ch, data|
          status        = data.read_long
          command_buffer(command) << [:status, status]
        end

        channel.on_request("exit-signal") do |ch, data|
          @logger.debug("exit-signal for [#{command}]")
        end

        channel.exec(command[:script]) do |ch, success|
          started = true
          @logger.debug("command [#{command}] started")
          unless success
            command_buffer(command).concat([[:error, "FAILED: couldn't execute command (ssh.channel.exec)"],
                                            [:status, -1]])
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
          buffer.delete_if do |(type, data)|
            if type == :status
              status = data
              true
            end
          end
          @logger.debug("command #{command} got new output: #{buffer.inspect}")
          command.suspended_action << CommandUpdate[buffer.dup, status]
          if status
            @logger.debug("command [#{command}] finished with status #{status}")
            finished_commands << command
          end
          buffer.clear
        end
      end

      finished_commands.each { |command| clear_command(command) }

      @refresh_planned = false
      plan_next_refresh
    end

    private

    def session(host, user)
      @logger.debug("opening session to #{user}@#{host}")
      @sessions[[host, user]] ||= Net::SSH.start(host, user)
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
      close_session_if_inactive(command.host, command.ssh_user)
      @command_buffer.delete(command)
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
