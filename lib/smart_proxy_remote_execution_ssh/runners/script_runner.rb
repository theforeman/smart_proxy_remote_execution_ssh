require 'fileutils'
require 'smart_proxy_dynflow/runner/process_manager_command'
require 'smart_proxy_dynflow/process_manager'
require 'smart_proxy_remote_execution_ssh/multiplexed_ssh_connection'

module Proxy::RemoteExecution::Ssh::Runners
  class EffectiveUserMethod
    attr_reader :effective_user, :ssh_user, :effective_user_password, :password_sent

    def initialize(effective_user, ssh_user, effective_user_password)
      @effective_user = effective_user
      @ssh_user = ssh_user
      @effective_user_password = effective_user_password.to_s
      @password_sent = false
    end

    def on_data(received_data, io_buffer)
      if received_data.match(login_prompt)
        io_buffer.add_data(effective_user_password + "\n")
        @password_sent = true
      end
    end

    def filter_password?(received_data)
      !@effective_user_password.empty? && @password_sent && received_data.match(Regexp.escape(@effective_user_password))
    end

    def sent_all_data?
      effective_user_password.empty? || password_sent
    end

    def reset
      @password_sent = false
    end

    def cli_command_prefix; end

    def login_prompt; end
  end

  class SudoUserMethod < EffectiveUserMethod
    LOGIN_PROMPT = 'rex login: '.freeze

    def login_prompt
      LOGIN_PROMPT
    end

    def cli_command_prefix
      "sudo -p '#{LOGIN_PROMPT}' -u #{effective_user} "
    end
  end

  class DzdoUserMethod < EffectiveUserMethod
    LOGIN_PROMPT = /password/i.freeze

    def login_prompt
      LOGIN_PROMPT
    end

    def cli_command_prefix
      "dzdo -u #{effective_user} "
    end
  end

  class SuUserMethod < EffectiveUserMethod
    LOGIN_PROMPT = /Password: /i.freeze

    def login_prompt
      LOGIN_PROMPT
    end

    def cli_command_prefix
      "su - #{effective_user} -c "
    end
  end

  class NoopUserMethod
    def on_data(_, _); end

    def filter_password?(received_data)
      false
    end

    def sent_all_data?
      true
    end

    def cli_command_prefix; end

    def reset; end
  end

  class ScriptRunner < Proxy::Dynflow::Runner::Base
    include Proxy::Dynflow::Runner::ProcessManagerCommand
    include CommandLogging

    attr_reader :execution_timeout_interval

    EXPECTED_POWER_ACTION_MESSAGES = ['restart host', 'shutdown host'].freeze
    DEFAULT_REFRESH_INTERVAL = 1

    UNSHARE_PREFIX = 'unshare --fork --kill-child'.freeze

    def initialize(options, user_method, suspended_action: nil)
      super suspended_action: suspended_action
      @host = options.fetch(:hostname)
      @script = options.fetch(:script)
      @ssh_user = options.fetch(:ssh_user, 'root')
      @ssh_port = options.fetch(:ssh_port, 22)
      @host_public_key = options.fetch(:host_public_key, nil)
      @execution_timeout_interval = options.fetch(:execution_timeout_interval, nil)

      @client_private_key_file = settings.ssh_identity_key_file
      @local_working_dir = options.fetch(:local_working_dir, settings.local_working_dir)
      @remote_working_dir = options.fetch(:remote_working_dir, settings.remote_working_dir.shellescape)
      @socket_working_dir = options.fetch(:socket_working_dir, settings.socket_working_dir)
      @cleanup_working_dirs = options.fetch(:cleanup_working_dirs, settings.cleanup_working_dirs)
      @first_execution = options.fetch(:first_execution, false)
      @user_method = user_method
      @options = options
    end

    def self.build(options, suspended_action:)
      effective_user = options.fetch(:effective_user, nil)
      ssh_user = options.fetch(:ssh_user, 'root')
      effective_user_method = options.fetch(:effective_user_method, 'sudo')

      user_method = if effective_user.nil? || effective_user == ssh_user
                      NoopUserMethod.new
                    elsif effective_user_method == 'sudo'
                      SudoUserMethod.new(effective_user, ssh_user,
                                         options.fetch(:secrets, {}).fetch(:effective_user_password, nil))
                    elsif effective_user_method == 'dzdo'
                      DzdoUserMethod.new(effective_user, ssh_user,
                                         options.fetch(:secrets, {}).fetch(:effective_user_password, nil))
                    elsif effective_user_method == 'su'
                      SuUserMethod.new(effective_user, ssh_user,
                                       options.fetch(:secrets, {}).fetch(:effective_user_password, nil))
                    else
                      raise "effective_user_method '#{effective_user_method}' not supported"
                    end

      new(options, user_method, suspended_action: suspended_action)
    end

    def start
      Proxy::RemoteExecution::Utils.prune_known_hosts!(@host, @ssh_port, logger) if @first_execution
      ensure_local_directory(@socket_working_dir)
      @connection = MultiplexedSSHConnection.new(@options.merge(:id => @id), logger: logger)
      @connection.establish!
      preflight_checks
      prepare_start
      script = initialization_script
      logger.debug("executing script:\n#{indent_multiline(script)}")
      trigger(script)
    rescue StandardError, NotImplementedError => e
      logger.error("error while initializing command #{e.class} #{e.message}:\n #{e.backtrace.join("\n")}")
      publish_exception('Error initializing command', e)
    end

    def trigger(*args)
      run_async(*args)
    end

    def preflight_checks
      script = cp_script_to_remote("#!/bin/sh\nexec true")
      ensure_remote_command(script,
        error: 'Failed to execute script on remote machine, exit code: %{exit_code}.'
      )
      unless @user_method.is_a? NoopUserMethod
        ensure_effective_user_access(script)
        ensure_remote_command("#{@user_method.cli_command_prefix} #{script}",
                              error: 'Failed to change to effective user, exit code: %{exit_code}',
                              tty: true,
                              user_method: @user_method,
                              close_stdin: false)
      end
      # The path should already be escaped
      ensure_remote_command("rm #{script}")
    end

    def prepare_start
      @remote_script = cp_script_to_remote
      @output_path = File.join(File.dirname(@remote_script), 'output')
      @exit_code_path = File.join(File.dirname(@remote_script), 'exit_code')
      @pid_path = File.join(File.dirname(@remote_script), 'pid')
      su_method = @user_method.instance_of?(SuUserMethod)
      wrapper = <<~SCRIPT
        if [ "$1" = "inner" ]; then
          echo \$$ > #{@pid_path}
          (
            #{@user_method.cli_command_prefix}#{su_method ? "'exec #{@remote_script} < /dev/null '" : "#{@remote_script} < /dev/null"}
            echo \$? >#{@exit_code_path}
          ) | tee #{@output_path}
          if [ -f #{@exit_code_path} ] && [ $(wc -l < #{@exit_code_path}) -gt 0 ]; then
            exit $(cat #{@exit_code_path})
          else
            exit 1
          fi
        else
          UNSHARE=''
          if #{UNSHARE_PREFIX} true >/dev/null 2>/dev/null; then
              UNSHARE='#{UNSHARE_PREFIX}'
          fi
          exec $UNSHARE "$0" inner
        fi
      SCRIPT
      @remote_script_wrapper = upload_data(
        wrapper,
        File.join(File.dirname(@remote_script), 'script-wrapper'))
      ensure_effective_user_access(@remote_script_wrapper, @remote_script)
      @remote_script_wrapper
    end

    # the script that initiates the execution
    def initialization_script
      # pipe the output to tee while capturing the exit code in a file
      @remote_script_wrapper
    end

    def refresh
      return if @process_manager.nil?
      super
    ensure
      check_expecting_disconnect
    end

    def kill
      if @process_manager&.started?
        run_sync("kill $(cat #{@pid_path})")
      else
        logger.debug('connection closed')
      end
    rescue StandardError => e
      publish_exception('Unexpected error', e, false)
    end

    def timeout
      @logger.debug('job timed out')
      super
    end

    def timeout_interval
      execution_timeout_interval
    end

    def close_session
      raise 'Control socket file does not exist' unless File.exist?(socket_file)
      @logger.debug("Sending exit request for session #{@ssh_user}@#{@host}")
      @connection.disconnect!
    end

    def close
      run_sync("rm -rf #{remote_command_dir}") if should_cleanup?
    rescue StandardError => e
      publish_exception('Error when removing remote working dir', e, false)
    ensure
      close_session if @process_manager
      FileUtils.rm_rf(local_command_dir) if Dir.exist?(local_command_dir) && @cleanup_working_dirs
    end

    def publish_data(data, type, pm = nil)
      pm ||= @process_manager
      data = data.dup if data.frozen?
      super(data.force_encoding('UTF-8'), type) unless @user_method.filter_password?(data)
      @user_method.on_data(data, pm.stdin) if pm
    end

    private

    def indent_multiline(string)
      string.lines.map { |line| "  | #{line}" }.join
    end

    def should_cleanup?
      @process_manager && @cleanup_working_dirs
    end

    def settings
      Proxy::RemoteExecution::Ssh::Plugin.settings
    end

    # Initiates run of the remote command and yields the data when
    # available. The yielding doesn't happen automatically, but as
    # part of calling the `refresh` method.
    def run_async(command)
      raise 'Async command already in progress' if @process_manager&.started?

      @user_method.reset
      cmd = @connection.command([tty_flag(true), command].flatten.compact)
      log_command(cmd)
      initialize_command(*cmd)

      true
    end

    def run_started?
      @process_manager&.started? && @user_method.sent_all_data?
    end

    def tty_flag(tty)
      '-tt' if tty
    end

    def run_sync(command, stdin: nil, close_stdin: true, tty: false, user_method: nil)
      cmd = @connection.command([tty_flag(tty), command].flatten.compact)
      log_command(cmd)
      pm = Proxy::Dynflow::ProcessManager.new(cmd)
      set_pm_debug_logging(pm, user_method: user_method)
      pm.start!
      unless pm.status
        pm.stdin.io.puts(stdin) if stdin
        pm.stdin.io.close if close_stdin
        pm.run!
      end
      pm
    end

    def prepare_known_hosts
      path = local_command_file('known_hosts')
      if @host_public_key
        write_command_file_locally('known_hosts', "#{@host} #{@host_public_key}")
      end
      return path
    end

    def local_command_dir
      File.join(@local_working_dir, 'foreman-proxy', "foreman-ssh-cmd-#{@id}")
    end

    def local_command_file(filename)
      File.join(ensure_local_directory(local_command_dir), filename)
    end

    def socket_file
      File.join(ensure_local_directory(@socket_working_dir), @id)
    end

    def remote_command_dir
      File.join(@remote_working_dir, "foreman-ssh-cmd-#{id}")
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

    def cp_script_to_remote(script = @script, name = 'script')
      path = remote_command_file(name)
      @logger.debug("copying script to #{path}:\n#{indent_multiline(script)}")
      upload_data(sanitize_script(script), path)
    end

    def upload_data(data, path, permissions = 500)
      ensure_remote_directory File.dirname(path)
      # We use tee here to pipe stdin coming from ssh to a file at $path, while silencing its output
      # This is used to write to $path with elevated permissions, solutions using cat and output redirection
      # would not work, because the redirection would happen in the non-elevated shell.
      command = "tee #{path} >/dev/null && chmod #{permissions} #{path}"

      @logger.debug("Sending data to #{path} on remote host:\n#{data}")
      ensure_remote_command(command,
        stdin: data,
        error: "Unable to upload file to #{path} on remote system, exit code: %{exit_code}"
      )

      path
    end

    def upload_file(local_path, remote_path)
      mode = File.stat(local_path).mode.to_s(8)[-3..-1]
      @logger.debug("Uploading local file: #{local_path} as #{remote_path} with #{mode} permissions")
      upload_data(File.read(local_path), remote_path, mode)
    end

    def ensure_remote_directory(path)
      ensure_remote_command("mkdir -p #{path}",
        error: "Unable to create directory #{path} on remote system, exit code: %{exit_code}"
      )
    end

    def ensure_remote_command(cmd, error: nil, **kwargs)
      if (pm = run_sync(cmd, **kwargs)).status != 0
        msg = error || 'Failed to run command %{command} on remote machine, exit code: %{exit_code}'
        raise(msg % { command: cmd, exit_code: pm.status })
      end
    end

    def sanitize_script(script)
      script.tr("\r", '')
    end

    def write_command_file_locally(filename, content)
      path = local_command_file(filename)
      ensure_local_directory(File.dirname(path))
      File.write(path, content)
      return path
    end

    # when a remote server disconnects, it's hard to tell if it was on purpose (when calling reboot)
    # or it's an error. When it's expected, we expect the script to produce 'restart host' as
    # its last command output
    def check_expecting_disconnect
      last_output = @continuous_output.raw_outputs.find { |d| d['output_type'] == 'stdout' }
      return unless last_output

      if EXPECTED_POWER_ACTION_MESSAGES.any? { |message| last_output['output'] =~ /^#{message}/ }
        @expecting_disconnect = true
      end
    end

    def ensure_effective_user_access(*paths)
      unless @user_method.is_a? NoopUserMethod
        ensure_remote_command("setfacl -m u:#{@user_method.effective_user}:rx #{paths.join(' ')}")
      end
    end
  end
end
