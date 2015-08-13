require 'smart_proxy_remote_execution_ssh/connector'

module Support
  class DummyConnector < Proxy::RemoteExecution::Ssh::Connector
    attr_reader :host, :user, :options

    def initialize(host, user, options = {})
      super
      DummyConnector.last = self
      @options = options
    end

    def async_run(command, &block)
      if @block
        raise "The DummyConnector does not support multiple async executions"
      end
      log_call(:async_run, command)
      @block = block
      return true
    end

    def run(command)
      log_call(:run, command)
      return *self.class.mocked_run_data
    end

    def upload_file(local_path, remote_path)
      log_call(:upload_file, local_path, remote_path)
    end

    def refresh
      return unless @block
      if data = self.class.mocked_async_run_data.shift
        @block.call(data)
      end
    end

    def inactive?
      self.class.inactive?
    end

    def close
      @block = nil
    end

    private

    def log_call(*args)
      self.class.log << ["#{@user}@#{@host}"].concat(args)
    end

    class << self
      attr_reader :log, :mocked_async_run_data, :finished
      attr_accessor :last

      def inactive?
        if mocked_async_run_data.empty?
          @finished.success(true)
          return true
        end
      end

      def mocked_run_data
        return (@mocked_run_data.shift || [0, "Output"])
      end

      def reset
        @last_connector = nil
        @finished = Concurrent.future
        @log = []
        @mocked_async_run_data = []
        @mocked_run_data = []
      end

      def wait
        @finished.wait(5)
        unless @finished.success?
          raise "Error waiting for dummy connector to finish"
        end
      end
    end
  end
end
