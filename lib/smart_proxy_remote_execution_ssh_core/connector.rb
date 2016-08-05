require 'net/ssh'
require 'net/scp'

module Proxy
  module RemoteExecution
    module Ssh
      # Service that handles running external commands for Actions::Command
      # Dynflow action. It runs just one (actor) thread for all the commands
      # running in the system and updates the Dynflow actions periodically.
      class Connector
        MAX_PROCESS_RETRIES = 3

        def initialize(host, port, user, options = {})
          @host = host
          @port = port
          @user = user
          @logger = options[:logger] || Logger.new($stderr)
          @client_private_key_file = options[:client_private_key_file]
          @known_hosts_file = options[:known_hosts_file]
        end

        # Initiates run of the remote command and yields the data when
        # available. The yielding doesn't happen automatically, but as
        # part of calling the `refresh` method.
        def async_run(command)
          started = false
          session.open_channel do |channel|
            channel.request_pty

            channel.on_data { |ch, data| yield CommandUpdate::StdoutData.new(data) }

            channel.on_extended_data { |ch, type, data| yield CommandUpdate::StderrData.new(data) }

            # standard exit of the command
            channel.on_request("exit-status") { |ch, data| yield CommandUpdate::StatusData.new(data.read_long) }

            # on signal: sedning the signal value (such as 'TERM')
            channel.on_request("exit-signal") do |ch, data|
              yield(CommandUpdate::StatusData.new(data.read_string))
              ch.close
              # wait for the channel to finish so that we know at the end
              # that the session is inactive
              ch.wait
            end

            channel.exec(command) do |ch, success|
              started = true
              unless success
                CommandUpdate.encode_exception("Error initializing command #{command}", e).each do |data|
                  yield data
                end
              end
            end
          end
          session.process(0) until started
          return true
        end

        def run(command)
          output = ""
          exit_status = nil
          channel = session.open_channel do |ch|
            ch.on_data { |data| output.concat(data) }

            ch.on_extended_data { |_, _, data| output.concat(data) }

            ch.on_request("exit-status") { |_, data| exit_status = data.read_long }

            # on signal: sedning the signal value (such as 'TERM')
            ch.on_request("exit-signal") do |_, data|
              exit_status = data.read_string
              ch.close
              ch.wait
            end

            ch.exec command do |_, success|
              raise "could not execute command" unless success
            end
          end
          channel.wait
          return exit_status, output
        end

        # calls the callback registered in the `async_run` when some data
        # for the session are available
        def refresh
          return if @session.nil?
          tries = 0
          begin
            session.process(0)
          rescue Net::SSH::Disconnect => e
            session.shutdown!
            raise e
          rescue => e
            @logger.error("Error while processing ssh channel: #{e.class} #{e.message}\n #{e.backtrace.join("\n")}")
            tries += 1
            if tries <= MAX_PROCESS_RETRIES
              retry
            else
              raise e
            end
          end
        end

        def upload_file(local_path, remote_path)
          ensure_remote_directory(File.dirname(remote_path))
          scp = Net::SCP.new(session)
          upload_channel = scp.upload(local_path, remote_path)
          upload_channel.wait
        ensure
          if upload_channel
            upload_channel.close
            upload_channel.wait
          end
        end

        def ensure_remote_directory(path)
          exit_code, output = run("mkdir -p #{path}")
          if exit_code != 0
            raise "Unable to create directory on remote system #{path}: exit code: #{exit_code}\n #{output}"
          end
        end

        def close
          @logger.debug("closing session to #{@user}@#{@host}")
          @session.close unless @session.nil? || @session.closed?
        end

        private

        def session
          @session ||= begin
                         @logger.debug("opening session to #{@user}@#{@host}")
                         Net::SSH.start(@host, @user, ssh_options)
                       end
        end

        def ssh_options
          ssh_options = {}
          ssh_options[:port] = @port if @port
          ssh_options[:keys] = [@client_private_key_file] if @client_private_key_file
          ssh_options[:user_known_hosts_file] = @known_hosts_file if @known_hosts_file
          ssh_options[:keys_only] = true
          # if the host public key is contained in the known_hosts_file,
          # verify it, otherwise, if missing, import it and continue
          ssh_options[:paranoid] = true
          ssh_options[:auth_methods] = ["publickey"]
          return ssh_options
        end
      end
    end
  end
end
