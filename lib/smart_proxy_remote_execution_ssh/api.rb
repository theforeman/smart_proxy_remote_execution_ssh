require 'net/ssh'
require 'base64'

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

      delete '/known_hosts/:name' do |name|
        do_authorize_any
        keys = Net::SSH::KnownHosts.search_for(name)
        return [204] if keys.empty?
        ssh_keys = keys.map { |key| Base64.strict_encode64 key.to_blob }
        Net::SSH::KnownHosts.hostfiles({}, :user)
          .map { |file| File.expand_path file }
          .select { |file| File.readable?(file) && File.writable?(file) }
          .each do |host_file|
            lines = File.foreach(host_file).reject do |line|
              ssh_keys.any? { |key| line.end_with? "#{key}\n" }
            end
            File.open(host_file, 'w') { |f| f.write lines.join }
          end
        204
      end
    end
  end
end
