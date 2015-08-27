module Proxy::RemoteExecution::Ssh
  # update sent back to the suspended action
  class CommandUpdate
    attr_reader :buffer, :exit_status

    def initialize(buffer)
      @buffer = buffer
      extract_exit_status
    end

    def extract_exit_status
      @buffer.delete_if do |data|
        if data.is_a? StatusData
          @exit_status = data.data
          true
        end
      end
    end

    def buffer_to_hash
      buffer.map(&:to_hash)
    end

    def self.encode_exception(description, exception, fatal = true)
      ret = [DebugData.new("#{description}\n#{exception.class} #{exception.message}")]
      ret << StatusData.new('EXCEPTION') if fatal
      return ret
    end

    class Data
      attr_reader :data, :timestamp

      def initialize(data, timestamp = Time.now)
        @data = data
        @timestamp = timestamp
      end

      def data_type
        raise NotImplemented
      end

      def to_hash
        { :output_type => data_type,
          :output => data,
          :timestamp => timestamp.to_f }
      end
    end

    class StdoutData < Data
      def data_type
        :stdout
      end
    end

    class StderrData < Data
      def data_type
        :stderr
      end
    end

    class DebugData < Data
      def data_type
        :debug
      end
    end

    class StatusData < Data
      def data_type
        :status
      end
    end
  end
end
