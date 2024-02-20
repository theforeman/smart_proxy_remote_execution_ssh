require 'smart_proxy_remote_execution_ssh/command_logging'

module Proxy::RemoteExecution::Ssh::Runners
  class SensitiveString
    def initialize(value, mask: '*****')
      @value = value
      @mask = mask
    end

    def inspect
      '"' + to_s + '"'
    end

    def to_s
      @mask
    end

    def to_str
      @value
    end
  end

  class AuthenticationMethod
    attr_reader :name
    attr_accessor :errors
    def initialize(name, prompt: nil, password: nil)
      @name = name
      @prompt = prompt
      @password = password
      @errors = nil
    end

    def ssh_command_prefix
      return [] unless @password

      prompt = ['-P', @prompt] if @prompt
      [{'SSHPASS' => SensitiveString.new(@password)}, 'sshpass', '-e', prompt].compact
    end

    def ssh_options
      ["-o PreferredAuthentications=#{name}",
       "-o NumberOfPasswordPrompts=#{@password ? 1 : 0}"]
    end
  end

  class MultiplexedSSHConnection
    include CommandLogging

    attr_reader :logger
    def initialize(options, logger:)
      @logger = logger

      @id = options.fetch(:id)
      @host = options.fetch(:hostname)
      @script = options.fetch(:script)
      @ssh_user = options.fetch(:ssh_user, 'root')
      @ssh_port = options.fetch(:ssh_port, 22)
      @ssh_password = options.fetch(:secrets, {}).fetch(:ssh_password, nil)
      @key_passphrase = options.fetch(:secrets, {}).fetch(:key_passphrase, nil)
      @host_public_key = options.fetch(:host_public_key, nil)
      @verify_host = options.fetch(:verify_host, nil)
      @client_private_key_file = settings.ssh_identity_key_file

      @local_working_dir = options.fetch(:local_working_dir, settings.local_working_dir)
      @socket_working_dir = options.fetch(:socket_working_dir, settings.socket_working_dir)
      @socket = nil
    end

    def establish!
      @available_auth_methods ||= available_authentication_methods
      method = @available_auth_methods.find do |method|
        pm = try_auth_method(method)
        method.errors = pm.stderr
        if pm.status.zero?
          @available_auth_methods.unshift(method).uniq!
          true
        end
      end
      return method if method

      msg = "Could not establish connection to remote host using any available authentication method, tried #{@available_auth_methods.map(&:name).join(', ')}"
      method_errors = @available_auth_methods.map { |method| "Authentication method '#{method.name}' failed with:\n#{method.errors}" }.join("\n")
      raise "#{msg}\n\n#{method_errors}"
    end

    def disconnect!
      return unless connected?

      cmd = command(%w[-O exit])
      log_command(cmd, label: "Closing shared connection")
      pm = Proxy::Dynflow::ProcessManager.new(cmd)
      set_pm_debug_logging(pm)
      pm.run!
      @socket = nil
    end

    def connected?
      !@socket.nil?
    end

    def command(cmd)
      raise "Cannot build command to run over multiplexed connection without having an established connection" unless connected?

      ['ssh', reuse_ssh_options, cmd].flatten
    end

    private

    def try_auth_method(method)
      # running "ssh -f -N" instead of "ssh true" would be cleaner, but ssh
      # does not close its stderr which trips up the process manager which
      # expects all FDs to be closed

      full_command = [method.ssh_command_prefix, 'ssh', establish_ssh_options, method.ssh_options, @host,
                      'true'].flatten
      log_command(full_command)
      pm = Proxy::Dynflow::ProcessManager.new(full_command)
      pm.start!
      if pm.status
        raise pm.stderr.to_s
      else
        set_pm_debug_logging(pm)
        pm.stdin.io.close
        pm.run!
      end

      if pm.status.zero?
        logger.debug("Established connection using authentication method #{method.name}")
        @socket = socket_file
      else
        logger.debug("Failed to establish connection using authentication method #{method.name}")
      end
      pm
    end

    def settings
      Proxy::RemoteExecution::Ssh::Plugin.settings
    end

    def available_authentication_methods
      methods = []
      methods << AuthenticationMethod.new('password', password: @ssh_password) if @ssh_password
      if verify_key_passphrase
        methods << AuthenticationMethod.new('publickey', password: @key_passphrase, prompt: 'passphrase')
      end
      methods << AuthenticationMethod.new('gssapi-with-mic') if settings[:kerberos_auth]
      raise "There are no available authentication methods" if methods.empty?
      methods
    end

    def establish_ssh_options
      return @establish_ssh_options if @establish_ssh_options
      ssh_options = []
      ssh_options << "-o User=#{@ssh_user}"
      ssh_options << "-o Port=#{@ssh_port}" if @ssh_port
      ssh_options << "-o IdentityFile=#{@client_private_key_file}" if @client_private_key_file
      ssh_options << "-o IdentitiesOnly=yes"
      ssh_options << "-o StrictHostKeyChecking=accept-new"
      ssh_options << "-o UserKnownHostsFile=#{prepare_known_hosts}" if @host_public_key
      ssh_options << "-o LogLevel=#{ssh_log_level(true)}"
      ssh_options << "-o ControlMaster=auto"
      ssh_options << "-o ControlPath=#{socket_file}"
      ssh_options << "-o ControlPersist=yes"
      ssh_options << "-o ProxyCommand=none"
      ssh_options << "-o ServerAliveInterval=15"
      ssh_options << "-o ServerAliveCountMax=3" # This is the default, but let's be explicit
      @establish_ssh_options = ssh_options
    end

    def reuse_ssh_options
      ["-o", "ControlPath=#{@socket}", "-o", "LogLevel=#{ssh_log_level(false)}", @host]
    end

    def socket_file
      File.join(@socket_working_dir, @id)
    end

    def verify_key_passphrase
      command = ['ssh-keygen', '-y', '-f', File.expand_path(@client_private_key_file)]
      log_command(command, label: "Checking if private key has passphrase")
      pm = Proxy::Dynflow::ProcessManager.new(command)
      pm.start!

      raise pm.stderr.to_s if pm.status

      pm.stdin.io.close
      pm.run!

      if pm.status.zero?
        logger.debug("Private key is not protected with a passphrase")
        @key_passphrase = nil
      else
        logger.debug("Private key is protected with a passphrase")
      end

      return true if pm.status.zero? || @key_passphrase

      logger.debug("Private key is protected with a passphrase, but no passphrase was provided")
      false
    end

    def ssh_log_level(new_connection)
      new_connection ? settings[:ssh_log_level] : 'quiet'
    end
  end
end
