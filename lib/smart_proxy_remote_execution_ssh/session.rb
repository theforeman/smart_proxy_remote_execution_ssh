require 'smart_proxy_remote_execution_ssh/session'

module Proxy::RemoteExecution::Ssh
  # Service that handles running external commands for Actions::Command
  # Dynflow action. It runs just one (actor) thread for all the commands
  # running in the system and updates the Dynflow actions periodically.
  class Session < ::Dynflow::Actor
    def initialize(options = {})
      @clock = options[:clock] || Dynflow::Clock.spawn('proxy-dispatcher-clock')
      @logger = options[:logger] || Logger.new($stderr)
      @connector_class = options[:connector_class] || Connector
      @local_working_dir = options[:local_working_dir] || '/tmp/foreman-proxy-ssh/server'
      @remote_working_dir = options[:remote_working_dir] || '/tmp/foreman-proxy-ssh/client'
      @refresh_interval = options[:refresh_interval] || 1
      @client_private_key_file = Proxy::RemoteExecution::Ssh.private_key_file
      @command = options[:command]

      @command_buffer = []
      @refresh_planned = false

      reference.tell(:initialize_command)
    end

    def initialize_command
      @logger.debug("initalizing command [#{@command}]")
      open_connector
      remote_script = cp_script_to_remote
      if @command.effective_user && @command.effective_user != @command.ssh_user
        su_prefix = "su - #{@command.effective_user} -c "
      end
      output_path = File.join(File.dirname(remote_script), 'output')

      @connector.async_run("#{su_prefix}#{remote_script} | /usr/bin/tee #{output_path}") do |data|
        @command_buffer << data
      end
    rescue => e
      @logger.error("error while initalizing command #{e.class} #{e.message}:\n #{e.backtrace.join("\n")}")
      @command_buffer.concat(CommandUpdate.encode_exception("Error initializing command #{@command}", e))
      refresh
    ensure
      plan_next_refresh
    end

    def refresh
      @connector.refresh if @connector

      unless @command_buffer.empty?
        status = refresh_command_buffer
        if status
          finish_command
        end
      end
    rescue => e
      @command_buffer.concat(CommandUpdate.encode_exception("Failed to refresh the connector", e, false))
    ensure
      @refresh_planned = false
      plan_next_refresh
    end

    def refresh_command_buffer
      @logger.debug("command #{@command} got new output: #{@command_buffer.inspect}")
      command_update = CommandUpdate.new(@command_buffer)
      @command.suspended_action << command_update
      @command_buffer = []
      if command_update.exit_status
        @logger.debug("command [#{@command}] finished with status #{command_update.exit_status}")
        return command_update.exit_status
      end
    end

    def kill
      @logger.debug("killing command [#{@command}]")
      if @connector
        @connector.run("pkill -f #{remote_command_file('script')}")
      else
        @logger.debug("connection closed")
      end
    rescue => e
      @command_buffer.concat(CommandUpdate.encode_exception("Failed to kill the command", e, false))
      plan_next_refresh
    end

    def finish_command
      close
      dispatcher.tell([:finish_command, @command])
    end

    def dispatcher
      self.parent
    end

    def start_termination(*args)
      super
      close
      finish_termination
    end

    private

    def open_connector
      raise 'Connector already opened' if @connector
      options = { :logger => @logger }
      options[:known_hosts_file] = prepare_known_hosts
      options[:client_private_key_file] = @client_private_key_file
      @connector = @connector_class.new(@command.host, @command.ssh_user, options)
    end

    def local_command_dir
      File.join(@local_working_dir, @command.id)
    end

    def local_command_file(filename)
      File.join(local_command_dir, filename)
    end

    def remote_command_dir
      File.join(@remote_working_dir, @command.id)
    end

    def remote_command_file(filename)
      File.join(remote_command_dir, filename)
    end

    def ensure_local_directory(path)
      if File.exist?(path)
        raise "#{path} expected to be a directory" unless File.directory?(path)
      else
        FileUtils.mkdir_p(path)
      end
      return path
    end

    def cp_script_to_remote
      local_script_file = write_command_file_locally('script', @command.script)
      File.chmod(0777, local_script_file)
      remote_script_file = remote_command_file('script')
      @connector.upload_file(local_script_file, remote_script_file)
      return remote_script_file
    end

    def write_command_file_locally(filename, content)
      path = local_command_file(filename)
      ensure_local_directory(File.dirname(path))
      File.write(path, content)
      return path
    end

    def prepare_known_hosts
      path = local_command_file('known_hosts')
      if @command.host_public_key
        write_command_file_locally('known_hosts', "#{@command.host} #{@command.host_public_key}")
      end
      return path
    end

    def close
      @connector.close if @connector
      @connector = nil
    end

    def plan_next_refresh
      if @connector && !@refresh_planned
        @logger.debug("planning to refresh")
        @clock.ping(reference, Time.now + @refresh_interval, :refresh)
        @refresh_planned = true
      end
    end
  end
end
