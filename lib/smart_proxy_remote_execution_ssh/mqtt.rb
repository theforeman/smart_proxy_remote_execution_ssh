module Proxy::RemoteExecution::Ssh
  class MQTT
    require 'smart_proxy_remote_execution_ssh/mqtt/dispatcher'

    class << self
      def publish(topic, payload, retain: false, qos: 1)
        with_mqtt_client do |c|
          c.publish(topic, payload, retain, qos)
        end
      end

      def with_mqtt_client(&block)
        ::MQTT::Client.connect(Plugin.settings.mqtt_broker,
                               Plugin.settings.mqtt_port,
                               :ssl => Plugin.settings.mqtt_tls,
                               :cert_file => ::Proxy::SETTINGS.foreman_ssl_cert || ::Proxy::SETTINGS.ssl_certificate,
                               :key_file => ::Proxy::SETTINGS.foreman_ssl_key || ::Proxy::SETTINGS.ssl_private_key,
                               :ca_file => ::Proxy::SETTINGS.foreman_ssl_ca || ::Proxy::SETTINGS.ssl_ca_file,
                               &block)
      end
    end
  end
end
