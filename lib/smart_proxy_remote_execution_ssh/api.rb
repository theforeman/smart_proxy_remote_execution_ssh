module Proxy::RemoteExecution
  module Ssh

    class Api < ::Sinatra::Base
      include Sinatra::Authorization::Helpers

      get "/pubkey" do
        File.read(Ssh.public_key_file)
      end

      post "/session" do
        do_authorize_any
        session = Cockpit::Session.new(env)
        unless session.valid?
          return [ 400, "Invalid request: /ssh/session requires connection upgrade to 'raw'" ]
        end
        session.hijack!
        101
      end
    end
  end
end
