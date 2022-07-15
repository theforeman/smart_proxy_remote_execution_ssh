require 'smart_proxy_remote_execution_ssh/net_ssh_compat'
require 'forwardable'

module Proxy::RemoteExecution
  module Cockpit
    # A wrapper class around different kind of sockets to comply with Net::SSH event loop
    class BufferedSocket
      include Proxy::RemoteExecution::NetSSHCompat::BufferedIO
      extend Forwardable

      # The list of methods taken from OpenSSL::SSL::SocketForwarder for the object to act like a socket
      def_delegators(:@socket, :to_io, :addr, :peeraddr, :setsockopt,
                     :getsockopt, :fcntl, :close, :closed?, :do_not_reverse_lookup=)

      def initialize(socket)
        @socket = socket
        initialize_buffered_io
      end

      def recv
        raise NotImplementedError
      end

      def send
        raise NotImplementedError
      end

      def self.applies_for?(socket)
        raise NotImplementedError
      end

      def self.build(socket)
        klass = [OpenSSLBufferedSocket, MiniSSLBufferedSocket, StandardBufferedSocket].find do |potential_class|
          potential_class.applies_for?(socket)
        end
        raise "No suitable implementation of buffered socket available for #{socket.inspect}" unless klass
        klass.new(socket)
      end
    end

    class StandardBufferedSocket < BufferedSocket
      def_delegators(:@socket, :send, :recv)

      def self.applies_for?(socket)
        socket.respond_to?(:send) && socket.respond_to?(:recv)
      end
    end

    class OpenSSLBufferedSocket < BufferedSocket
      def self.applies_for?(socket)
        socket.is_a? ::OpenSSL::SSL::SSLSocket
      end
      def_delegators(:@socket, :read_nonblock, :write_nonblock, :close)

      def recv(count)
        res = ""
        begin
          # To drain a SSLSocket before we can go back to the event
          # loop, we need to repeatedly call read_nonblock; a single
          # call is not enough.
          loop do
            res += @socket.read_nonblock(count)
          end
        rescue IO::WaitReadable
          # Sometimes there is no payload after reading everything
          # from the underlying socket, but a empty string is treated
          # as EOF by Net::SSH. So we block a bit until we have
          # something to return.
          if res == ""
            IO.select([@socket.to_io])
            retry
          else
            res
          end
        rescue IO::WaitWritable
          # A renegotiation is happening, let it proceed.
          IO.select(nil, [@socket.to_io])
          retry
        end
      end

      def send(mesg, flags)
        @socket.write_nonblock(mesg)
      rescue IO::WaitWritable
        0
      rescue IO::WaitReadable
        IO.select([@socket.to_io])
        retry
      end
    end

    class MiniSSLBufferedSocket < BufferedSocket
      def self.applies_for?(socket)
        socket.is_a? ::Puma::MiniSSL::Socket
      end
      def_delegators(:@socket, :read_nonblock, :write_nonblock, :close)

      def recv(count)
        @socket.read_nonblock(count)
      end

      def send(mesg, flags)
        @socket.write_nonblock(mesg)
      end

      def closed?
        @socket.to_io.closed?
      end
    end

    class Session
      include ::Proxy::Log

      def initialize(env)
        @env = env
        @open_ios = []
      end

      def valid?
        @env["HTTP_CONNECTION"] == "upgrade" && @env["HTTP_UPGRADE"].to_s.split(',').any? { |part| part.strip == "raw" }
      end

      def hijack!
        @socket = nil
        if @env['ext.hijack!']
          @socket = @env['ext.hijack!'].call
        elsif @env['rack.hijack?']
          begin
            @env['rack.hijack'].call
          rescue NotImplementedError
            # This is fine
          end
          @socket = @env['rack.hijack_io']
        end
        raise 'Internal error: request hijacking not available' unless @socket
        ssh_on_socket
      end

      private

      def ssh_on_socket
        with_error_handling { system_ssh_loop }
      end

      def with_error_handling
        yield
      rescue SystemCallError => e
        send_error(400, e.message)
      rescue SocketError => e
        send_error(400, e.message)
      rescue Exception => e
        logger.error e.message
        logger.debug e.backtrace.join("\n")
        send_error(500, "Internal error") unless @started
      ensure
        unless buf_socket.closed?
          buf_socket.wait_for_pending_sends
          buf_socket.close
        end
      end

      def system_ssh_loop
        in_read, in_write   = IO.pipe
        out_read, out_write = IO.pipe
        err_read, err_write = IO.pipe

        # Force the script runner to initialize its logger
        script_runner.logger
        pid = spawn(*script_runner.send(:get_args, command), :in => in_read, :out => out_write, :err => err_write)
        [in_read, out_write, err_write].each(&:close)

        send_start
        # Not SSL buffer, but the interface kinda matches
        out_buf = MiniSSLBufferedSocket.new(out_read)
        err_buf = MiniSSLBufferedSocket.new(err_read)
        in_buf  = MiniSSLBufferedSocket.new(in_write)

        inner_system_ssh_loop out_buf, err_buf, in_buf, pid
      end

      def inner_system_ssh_loop(out_buf, err_buf, in_buf, pid)
        err_buf_raw = ''
        loop do
          readers = [buf_socket, out_buf, err_buf].reject { |io| io.closed? }
          writers = [buf_socket, in_buf].select { |io| io.pending_writes? }
          # Prime the sockets for reading
          ready_readers, ready_writers = IO.select(readers, writers)
          (ready_readers || []).each { |reader| reader.close if reader.fill.zero? }

          proxy_data(out_buf, in_buf)
          if buf_socket.closed?
            script_runner.close_session
          end

          if out_buf.closed?
            code = Process.wait2(pid).last.exitstatus
            send_start if code.zero? # TODO: Why?
            err_buf_raw += "Process exited with code #{code}.\r\n"
            break
          end

          if err_buf.available.positive?
            err_buf_raw += err_buf.read_available
          end

          flush_pending_writes(ready_writers || [])
        end
      rescue # rubocop:disable Style/RescueStandardError
        send_error(400, err_buf_raw) unless @started
      ensure
        [out_buf, err_buf, in_buf].each(&:close)
      end

      def proxy_data(out_buf, in_buf)
        { out_buf => buf_socket, buf_socket => in_buf }.each do |src, dst|
          dst.enqueue(src.read_available) if src.available.positive?
          dst.close if src.closed?
        end
      end

      def flush_pending_writes(writers)
        writers.each do |writer|
          writer.respond_to?(:send_pending) ? writer.send_pending : writer.flush
        end
      end

      def send_start
        unless @started
          @started = true
          buf_socket.enqueue("Status: 101\r\n")
          buf_socket.enqueue("Connection: upgrade\r\n")
          buf_socket.enqueue("Upgrade: raw\r\n")
          buf_socket.enqueue("\r\n")
          buf_socket.send_pending
        end
      end

      def send_error(code, msg)
        buf_socket.enqueue("Status: #{code}\r\n")
        buf_socket.enqueue("Connection: close\r\n")
        buf_socket.enqueue("\r\n")
        buf_socket.enqueue(msg)
        buf_socket.send_pending
      end

      def params
        @params ||= MultiJson.load(@env["rack.input"].read)
      end

      def key_file
        @key_file ||= Proxy::RemoteExecution::Ssh.private_key_file
      end

      def buf_socket
        @buf_socket ||= BufferedSocket.build(@socket)
      end

      def command
        params["command"]
      end

      def host
        params["hostname"]
      end

      def script_runner
        @script_runner ||= Proxy::RemoteExecution::Ssh::Runners::ScriptRunner.build(
          runner_params,
          suspended_action: nil
        )
      end

      def runner_params
        ret = { secrets: {} }
        ret[:secrets][:ssh_password] = params["ssh_password"] if params["ssh_password"]
        ret[:secrets][:key_passphrase] = params["ssh_key_passphrase"] if params["ssh_key_passphrase"]
        ret[:ssh_port] = params["ssh_port"] if params["ssh_port"]
        ret[:ssh_user] = params["ssh_user"]
        # For compatibility only
        ret[:script] = nil
        ret[:hostname] = host
        ret
      end
    end
  end
end
