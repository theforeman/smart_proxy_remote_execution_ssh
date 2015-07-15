require 'smart_proxy_ssh/connector'

module Proxy::Ssh
  # Service that handles running external commands for Actions::Command
  # Dynflow action. It runs just one (actor) thread for all the commands
  # running in the system and updates the Dynflow actions periodically.
  class Dispatcher < ::Dynflow::Actor

    # command comming from action
    class Command
      attr_reader :id, :host, :ssh_user, :effective_user, :script, :suspended_action

      def initialize(data)
        validate!(data)

        @id               = data[:id]
        @host             = data[:host]
        @ssh_user         = data[:ssh_user]
        @effective_user   = data[:effective_user]
        @script           = data[:script]
        @suspended_action = data[:suspended_action]
      end

      def validate!(data)
        required_fields = [:id, :host, :ssh_user, :script, :suspended_action]
        missing_fields = required_fields.find_all { |f| !data[f] }
        raise ArgumentError, "Missing fields: #{missing_fields}" unless missing_fields.empty?
      end
    end

    # update sent back to the suspended action
    class CommandUpdate
      attr_reader :buffer, :exit_status

      def initialize(buffer, exit_status)
        @buffer      = buffer
        @exit_status = exit_status
      end

      def buffer_to_hash
        buffer.map do |buffer_data|
          { :output_type => buffer_data.data_type,
            :output      => buffer_data.data,
            :timestamp   => buffer_data.timestamp.to_f }
        end
      end
    end

    def initialize(options = {})
      @clock              = options[:clock] || Dynflow::Clock.spawn('proxy-dispatcher-clock')
      @logger             = options[:logger] || Logger.new($stderr)
      @connector_class    = options[:connector_class] || Connector
      @local_working_dir  = options[:local_working_dir] || '/tmp/foreman-proxy-ssh/server'
      @remote_working_dir = options[:remote_working_dir] || '/tmp/foreman-proxy-ssh/client'
      @refresh_interval   = options[:refresh_interval] || 1

      @connectors        = {}
      @command_buffer    = Hash.new { |h, k| h[k] = [] }
      @process_by_output = {}
      @process_buffer    = {}
      @refresh_planned = false
    end

    def initialize_command(command)
      @logger.debug("initalizing command [#{command}]")
      connector = self.connector(command.host, command.ssh_user)
      remote_script = cp_script_to_remote(connector, command)
      if command.effective_user && command.effective_user != command.ssh_user
        su_prefix = "su - #{command.effective_user} -c "
      end
      output_path = File.join(File.dirname(remote_script), 'output')


      connector.async_run("#{su_prefix}#{remote_script} | /usr/bin/tee #{ output_path }") do |data|
        command_buffer(command) << data
      end
    rescue => e
      @logger.error("error while initalizing command #{e.class} #{e.message}:\n #{e.backtrace.join("\n")}")
      command_buffer(command).concat([Connector::DebugData.new("Exception: #{e.class} #{e.message}"),
                                      Connector::StatusData.new('INIT_ERROR')])
    ensure
      plan_next_refresh
    end

    def refresh
      finished_commands = []
      refresh_connectors

      @command_buffer.each do |command, buffer|
        unless buffer.empty?
          status = nil
          @logger.debug("command #{command} got new output: #{buffer.inspect}")
          buffer.delete_if do |data|
            if data.is_a? Connector::StatusData
              status = data.data
              true
            end
          end
          command.suspended_action << CommandUpdate.new(buffer, status)
          if status
            @logger.debug("command [#{command}] finished with status #{status}")
            finished_commands << command
          end
          clear_command(command)
        end
      end

      finished_commands.each { |command| finish_command(command) }
      close_inactive_connectors
    ensure
      @refresh_planned = false
      plan_next_refresh
    end

    def kill(command)
      @logger.debug("killing command [#{command}]")
      connector(command.host, command.ssh_user).run("pkill -f #{ remote_script_file(command) }")
    end

    protected

    def connector(host, user)
      @connectors[[host, user]] ||= @connector_class.new(host, user, @logger)
    end

    def local_script_dir(command)
      File.join(@local_working_dir, command.id)
    end

    def local_script_file(command)
      File.join(local_script_dir(command), 'script')
    end

    def remote_script_dir(command)
      File.join(@remote_working_dir, command.id)
    end

    def remote_script_file(command)
      File.join(remote_script_dir(command), 'script')
    end

    def ensure_local_directory(path)
      if File.exists?(path)
        raise "#{ path } expected to be a directory" unless File.directory?(path)
      else
        FileUtils.mkdir_p(path)
      end
      return path
    end

    def cp_script_to_remote(connector, command)
      local_script_file = write_script_locally(command)
      remote_script_file = File.join(remote_script_dir(command), 'script')
      connector.upload_file(local_script_file, remote_script_file)
      return remote_script_file
    end

    def write_script_locally(command)
      path = local_script_file(command)
      ensure_local_directory(File.dirname(path))
      File.write(path, command.script)
      File.chmod(0777, path)
      return path
    end

    def close_inactive_connectors
      @connectors.delete_if do |_, connector|
        if connector.inactive?
          connector.close
          true
        end
      end
    end

    def refresh_connectors
      @logger.debug("refreshing #{@connectors.size} connectors")

      @connectors.values.each { |connector| connector.refresh }
    end

    def command_buffer(command)
      @command_buffer[command]
    end

    def clear_command(command)
      @command_buffer[command] = []
    end

    def finish_command(command)
      @command_buffer.delete(command)
    end

    def plan_next_refresh
      if @connectors.any? && !@refresh_planned
        @logger.debug("planning to refresh")
        @clock.ping(reference, Time.now + @refresh_interval, :refresh)
        @refresh_planned = true
      end
    end
  end
end
