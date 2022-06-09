# lib/command_logging.rb

module Proxy::RemoteExecution::Ssh::Runners
  module CommandLogging
    def log_command(command, label: "Running")
      command = command.join(' ')
      label = "#{label}: " if label
      logger.debug("#{label}#{command}")
    end

    def set_pm_debug_logging(pm, capture: false, user_method: nil)
      callback = proc do |data|
        data.each_line do |line|
          logger.debug(line.chomp) if user_method.nil? || !user_method.filter_password?(line)
          user_method.on_data(data, pm.stdin) if user_method
        end
        ''
      end
      pm.on_stdout(&callback)
      pm.on_stderr(&callback)
    end
  end
end
