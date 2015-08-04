module Proxy::RemoteExecution
  module Ssh
    class Api < ::Sinatra::Base
      get "/pubkey" do
        File.read(Ssh.public_key_file)
      end
    end
  end
end
