module Proxy
  module RemoteExecution
    module Ssh
      module Validators
        class SshLogLevel < ::Proxy::PluginValidators::Base
          def validate!(settings)
            setting_value = settings[@setting_name].to_s

            unless @params.include?(setting_value)
              raise ::Proxy::Error::ConfigurationError, "Parameter '#{@setting_name}' must be one of #{@params.join(', ')}"
            end

            current = ::Proxy::SETTINGS.log_level.to_s.downcase

            # regular log levels correspond to upcased ssh logger levels
            ssh, regular = [setting_value, current].map do |wanted|
              @params.each_with_index.find { |value, _index| value == wanted }.last
            end

            if ssh < regular
              raise ::Proxy::Error::ConfigurationError, "Parameter '#{@setting_name}' cannot be more verbose than regular log level (#{current})"
            end

            true
          end
        end

        class RexSshMode < ::Proxy::PluginValidators::Base
          def validate!(settings)
            setting_value = settings[@setting_name]

            unless @params.include?(setting_value)
              raise ::Proxy::Error::ConfigurationError, "Parameter '#{@setting_name}' must be one of #{@params.join(', ')}"
            end

            true
          end
        end
      end
    end
  end
end
