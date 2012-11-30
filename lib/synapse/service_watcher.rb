require_relative "./service_watcher/zookeeper"
require_relative "./service_watcher/stub_watcher"

module Synapse
  class ServiceWatcher

    attr_reader :backends, :name, :listen, :local_port, :server_options
    @watchers = {
      'zookeeper'=>Zookeeper,
      'stub'=>StubWatcher,
    }

    # the method which actually dispatches watcher creation requests
    def self.create(opts, synapse)
      raise ArgumentError, "Missing discovery method when trying to create watcher" \
        unless opts.has_key?('discovery') && opt['discovery'].has_key?('method')

      discovery_method = opts['discovery']['method']
      raise ArgumentError, "Invalid discovery method #{discovery_method}" \
        unless @watchers.has_key?(discovery_method)

      return @watchers[discovery_method].new(opts, synapse)
    end

    def initialize(opts={}, synapse)
      super()
      @synapse = synapse

      # set required service parameters
      %w{name discovery local_port}.each do |req|
        raise ArgumentError, "missing required option #{req}" unless opts[req]
      end

      @name = opts['name']
      @discovery = opts['discovery']
      @local_port = opts['local_port']

      # optional service parameters
      @listen = opts['listen'] || []
      @server_options = opts['server_options'] || ""
      @default_servers = opts['default_servers'] || []

      # set initial backends to default servers
      @backends = @default_servers
    end
  end
end
