require 'smart_proxy_remote_execution_ssh/session'

module Proxy::RemoteExecution::Ssh
  # Service that handles running external commands for Actions::Command
  # Dynflow action. It runs just one (actor) thread for all the commands
  # running in the system and updates the Dynflow actions periodically.
  class Dispatcher < ::Dynflow::Actor
    # command comming from action
    class Command
      attr_reader :id, :host, :ssh_user, :effective_user, :effective_user_method, :script, :host_public_key, :suspended_action

      def initialize(data)
        validate!(data)

        @id                    = data[:id]
        @host                  = data[:host]
        @ssh_user              = data[:ssh_user]
        @effective_user        = data[:effective_user]
        @effective_user_method = data[:effective_user_method] || 'su'
        @script                = data[:script]
        @host_public_key       = data[:host_public_key]
        @suspended_action      = data[:suspended_action]
      end

      def validate!(data)
        required_fields = [:id, :host, :ssh_user, :script, :suspended_action]
        missing_fields = required_fields.find_all { |f| !data[f] }
        raise ArgumentError, "Missing fields: #{missing_fields}" unless missing_fields.empty?
      end
    end

    def initialize(options = {})
      @clock                   = options[:clock] || Dynflow::Clock.spawn('proxy-dispatcher-clock')
      @logger                  = options[:logger] || Logger.new($stderr)

      @session_args = { :logger => @logger,
                        :clock => @clock,
                        :connector_class => options[:connector_class] || Connector,
                        :local_working_dir => options[:local_working_dir] || ::Proxy::RemoteExecution::Ssh::Plugin.settings.local_working_dir,
                        :remote_working_dir => options[:remote_working_dir] || ::Proxy::RemoteExecution::Ssh::Plugin.settings.remote_working_dir,
                        :client_private_key_file => Proxy::RemoteExecution::Ssh.private_key_file,
                        :refresh_interval => options[:refresh_interval] || 1 }

      @sessions = {}
    end

    def initialize_command(command)
      @logger.debug("initalizing command [#{command}]")
      open_session(command)
    rescue => exception
      handle_command_exception(command, exception)
    end

    def kill(command)
      @logger.debug("killing command [#{command}]")
      session = @sessions[command.id]
      session.tell(:kill) if session
    rescue => exception
      handle_command_exception(command, exception, false)
    end

    def finish_command(command)
      close_session(command)
    rescue => exception
      handle_command_exception(command, exception)
    end

    private

    def handle_command_exception(command, exception, fatal = true)
      @logger.error("error while dispatching command #{command} to session:"\
                    "#{exception.class} #{exception.message}:\n #{exception.backtrace.join("\n")}")
      command_data = CommandUpdate.encode_exception("Failed to dispatch the command", exception, fatal)
      command.suspended_action << CommandUpdate.new(command_data)
      close_session(command) if fatal
    end

    def open_session(command)
      raise "Session already opened for command #{command}" if @sessions[command.id]
      options = { :name => "proxy-ssh-session-#{command.host}-#{command.ssh_user}-#{command.id}",
                  :args => [@session_args.merge(:command => command)],
                  :supervise => true }
      @sessions[command.id] = Proxy::RemoteExecution::Ssh::Session.spawn(options)
    end

    def close_session(command)
      session = @sessions.delete(command.id)
      return unless session
      @logger.debug("closing session for command [#{command}], #{@sessions.size} session(s) left ")
      session.tell([:start_termination, Concurrent.future])
    end
  end
end
