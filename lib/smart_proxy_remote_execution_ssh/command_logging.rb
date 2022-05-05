# lib/command_logging.rb

module Proxy::RemoteExecution::Ssh::Runners
  module CommandLogging
    def log_command(command, label: "Running")
      command = command.join(' ')
      label = "#{label}: " if label
      logger.debug("#{label}#{command}")
    end

    def set_pm_debug_logging(pm, capture: false)
      pm.on_stdout do |data|
        data.each_line { |line| logger.debug(line.chomp) }
        ''
      end
      pm.on_stderr do |data|
        data.each_line { |line| logger.debug(line.chomp) }
        ''
      end
    end
  end
end
