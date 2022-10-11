require 'connection_pool'
require 'mqtt'

module Proxy::RemoteExecution::Ssh
  class MQTT
    class << self
      def connection_pool
        @mqtt_connection_pool ||= ::ConnectionPool.new(size: 5) { self.new }
      end

      def with_pooled_connection(&block)
        connection_pool.with do |client|
          client.with_connection(&block)
        end
      end
    end

    def initialize
      @client = ::MQTT::Client.new
      @client.host = ::Proxy::RemoteExecution::Ssh::Plugin.settings.mqtt_broker
      @client.port = ::Proxy::RemoteExecution::Ssh::Plugin.settings.mqtt_port
      @client.ssl = ::Proxy::RemoteExecution::Ssh::Plugin.settings.mqtt_tls
      @client.cert_file = ::Proxy::SETTINGS.foreman_ssl_cert || ::Proxy::SETTINGS.ssl_certificate
      @client.key_file = ::Proxy::SETTINGS.foreman_ssl_key || ::Proxy::SETTINGS.ssl_private_key
      @client.ca_file = ::Proxy::SETTINGS.foreman_ssl_ca || ::Proxy::SETTINGS.ssl_ca_file
    end

    def with_connection(&block)
      @client.connect(&block)
    end

    def close
      @client.disconnect if @client.connected?
    end
  end
end
