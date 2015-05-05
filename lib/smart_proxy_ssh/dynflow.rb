module Proxy::Ssh
  class Dynflow
    attr_reader :world

    def initialize
      @world = create_world
    end

    def create_world(options = {})
      options = default_world_options.merge(options)
      ::Dynflow::SimpleWorld.new(options)
    end

    def persistence_conn_string
      ENV['DYNFLOW_DB_CONN_STRING'] || 'sqlite:/'
    end

    def persistence_adapter
      ::Dynflow::PersistenceAdapters::Sequel.new persistence_conn_string
    end

    def default_world_options
      { logger_adapter: logger_adapter,
        persistence_adapter: persistence_adapter }
    end

    def logger_adapter
      ::Dynflow::LoggerAdapters::Simple.new $stderr, 2
    end


    def web_console
      require 'dynflow/web_console'
      world = @world
      dynflow_console = ::Dynflow::WebConsole.setup do
        set :world, world
      end
      dynflow_console
    end

  end
end
