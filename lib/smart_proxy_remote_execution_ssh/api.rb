require 'net/ssh'

# When hijacking the socket of a TLS connection with Puma, we get a
# Puma::MiniSSL::Socket, which isn't really a Socket.  We need to add
# recv and send for the benefit of the Net::SSH::BufferedIo mixin, and
# closed? for our own convenience.

module Puma
  module MiniSSL
    class Socket
      def closed?
        @socket.closed?
      end
      def recv(n)
        readpartial(n)
      end
      def send(mesg, flags)
        write(mesg)
      end
    end
  end
end

module Proxy::RemoteExecution
  module Ssh
    class Api < ::Sinatra::Base
      include Sinatra::Authorization::Helpers

      get "/pubkey" do
        File.read(Ssh.public_key_file)
      end

      post "/session" do
        do_authorize_any
        if env["HTTP_CONNECTION"] != "upgrade" or env["HTTP_UPGRADE"] != "raw"
          return [ 400, "Invalid request: /ssh/session requires connection upgrade to 'raw'" ]
        end

        params = MultiJson.load(env["rack.input"].read)
        key_file = Proxy::RemoteExecution::Ssh.private_key_file

        methods = %w(publickey)
        methods.unshift('password') if params["ssh_password"]

        ssh_options = { }
        ssh_options[:port] = params["ssh_port"] if params["ssh_port"]
        ssh_options[:keys] = [ key_file ] if key_file
        ssh_options[:password] = params["ssh_password"] if params["ssh_password"]
        ssh_options[:passphrase] = params[:ssh_key_passphrase] if params[:ssh_key_passphrase]
        ssh_options[:keys_only] = true
        ssh_options[:auth_methods] = methods
        ssh_options[:verify_host_key] = true
        ssh_options[:number_of_password_prompts] = 1

        socket = nil
        if env['WEBRICK_SOCKET']
          socket = env['WEBRICK_SOCKET']
        elsif env['rack.hijack?']
          begin
            env['rack.hijack'].call
          rescue NotImplementedError
          end
          socket = env['rack.hijack_io']
        end
        if !socket
          return [ 501, "Internal error: request hijacking not available" ]
        end

        ssh_on_socket(socket, params["command"], params["ssh_user"], params["hostname"], ssh_options)
        101
      end

      def ssh_on_socket(socket, command, ssh_user, host, ssh_options)
        started = false
        err_buf = ""
        socket.extend(Net::SSH::BufferedIo)

        send_start = -> {
          if !started
            started = true
            socket.enqueue("Status: 101\r\n")
            socket.enqueue("Connection: upgrade\r\n")
            socket.enqueue("Upgrade: raw\r\n")
            socket.enqueue("\r\n")
          end
        }

        send_error = -> (code, msg) {
          socket.enqueue("Status: #{code}\r\n")
          socket.enqueue("Connection: close\r\n")
          socket.enqueue("\r\n")
          socket.enqueue(msg)
        }

        begin
          Net::SSH.start(host, ssh_user, ssh_options) do |ssh|
            channel = ssh.open_channel do |ch|
              ch.exec(command) do |ch, success|
                raise "could not execute command" unless success

                ssh.listen_to(socket)

                ch.on_process do
                  if socket.available > 0
                    ch.send_data(socket.read_available)
                  end
                  if socket.closed?
                    ch.close
                  end
                end

                ch.on_data do |ch2, data|
                  send_start.call
                  socket.enqueue(data)
                end

                ch.on_request('exit-status') do |ch, data|
                  code = data.read_long
                  if code == 0
                    send_start.call
                  end
                  err_buf += "Process exited with code #{code}.\r\n"
                  ch.close
                end

                channel.on_request('exit-signal') do |ch, data|
                  err_buf += "Process was terminated with signal #{data.read_string}.\r\n"
                  ch.close
                end

                ch.on_extended_data do |ch2, type, data|
                  err_buf += data
                end
              end
            end

            channel.wait
            if !started
              send_error.call(400, err_buf)
            end
          end
        rescue Net::SSH::AuthenticationFailed => e
          send_error.call(401, e.message)
        rescue Exception => e
          logger.error e.message
          e.backtrace.each { |line| logger.debug line }
          send_error.call(500, "Internal error")
        end
        if not socket.closed?
          socket.wait_for_pending_sends
          socket.close
        end
      end

    end
  end
end
