require 'smart_proxy_remote_execution_ssh/connector'

module Proxy::RemoteExecution::Ssh
  # Service that handles running external commands for Actions::Command
  # Dynflow action. It runs just one (actor) thread for all the commands
  # running in the system and updates the Dynflow actions periodically.
  class Dispatcher < ::Dynflow::Actor
    # command comming from action
    class Command
      attr_reader :id, :host, :ssh_user, :effective_user, :script, :host_public_key, :suspended_action

      def initialize(data)
        validate!(data)

        @id               = data[:id]
        @host             = data[:host]
        @ssh_user         = data[:ssh_user]
        @effective_user   = data[:effective_user]
        @script           = data[:script]
        @host_public_key  = data[:host_public_key]
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
      @clock                   = options[:clock] || Dynflow::Clock.spawn('proxy-dispatcher-clock')
      @logger                  = options[:logger] || Logger.new($stderr)
      @connector_class         = options[:connector_class] || Connector
      @local_working_dir       = options[:local_working_dir] || '/tmp/foreman-proxy-ssh/server'
      @remote_working_dir      = options[:remote_working_dir] || '/tmp/foreman-proxy-ssh/client'
      @refresh_interval        = options[:refresh_interval] || 1
      @client_private_key_file = Proxy::RemoteExecution::Ssh.private_key_file

      @connectors        = {}
      @command_buffer    = Hash.new { |h, k| h[k] = [] }
      @refresh_planned = false
    end

    def initialize_command(command)
      @logger.debug("initalizing command [#{command}]")
      connector = self.connector_for_command(command)
      remote_script = cp_script_to_remote(connector, command)
      if command.effective_user && command.effective_user != command.ssh_user
        su_prefix = "su - #{command.effective_user} -c "
      end
      output_path = File.join(File.dirname(remote_script), 'output')

      connector.async_run("#{su_prefix}#{remote_script} | /usr/bin/tee #{output_path}") do |data|
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
          status = refresh_command_buffer(command, buffer)
          if status
            finished_commands << command
          end
        end
      end

      finished_commands.each { |command| finish_command(command) }
      close_inactive_connectors
    ensure
      @refresh_planned = false
      plan_next_refresh
    end

    def refresh_command_buffer(command, buffer)
      status = nil
      @logger.debug("command #{command} got new output: #{buffer.inspect}")
      buffer.delete_if do |data|
        if data.is_a? Connector::StatusData
          status = data.data
          true
        end
      end
      command.suspended_action << CommandUpdate.new(buffer, status)
      clear_command(command)
      if status
        @logger.debug("command [#{command}] finished with status #{status}")
        return status
      end
    end

    def kill(command)
      @logger.debug("killing command [#{command}]")
      connector_for_command(command).run("pkill -f #{remote_command_file(command, 'script')}")
    end

    protected

    def connector_for_command(command, only_if_exists = false)
      if connector = @connectors[[command.host, command.ssh_user]]
        return connector
      end
      return nil if only_if_exists
      @connectors[[command.host, command.ssh_user]] = open_connector(command)
    end

    def local_command_dir(command)
      File.join(@local_working_dir, command.id)
    end

    def local_command_file(command, filename)
      File.join(local_command_dir(command), filename)
    end

    def remote_command_dir(command)
      File.join(@remote_working_dir, command.id)
    end

    def remote_command_file(command, filename)
      File.join(remote_command_dir(command), filename)
    end

    def ensure_local_directory(path)
      if File.exist?(path)
        raise "#{path} expected to be a directory" unless File.directory?(path)
      else
        FileUtils.mkdir_p(path)
      end
      return path
    end

    def cp_script_to_remote(connector, command)
      local_script_file = write_command_file_locally(command, 'script', command.script)
      File.chmod(0777, local_script_file)
      remote_script_file = remote_command_file(command, 'script')
      connector.upload_file(local_script_file, remote_script_file)
      return remote_script_file
    end

    def write_command_file_locally(command, filename, content)
      path = local_command_file(command, filename)
      ensure_local_directory(File.dirname(path))
      File.write(path, content)
      return path
    end

    def open_connector(command)
      options = { :logger => @logger }
      options[:known_hosts_file] = prepare_known_hosts(command)
      options[:client_private_key_file] = @client_private_key_file
      @connector_class.new(command.host, command.ssh_user, options)
    end

    def prepare_known_hosts(command)
      path = local_command_file(command, 'known_hosts')
      if command.host_public_key
        write_command_file_locally(command, 'known_hosts', "#{command.host} #{command.host_public_key}")
      end
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

      @connectors.values.each do |connector|
        begin
          connector.refresh
        rescue => e
          @command_buffer.each do |command, buffer|
            if connector_for_command(command, false)
              buffer << Connector::DebugData.new("Exception: #{e.class} #{e.message}")
            end
          end
        end
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
