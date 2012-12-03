
module Synapse
  class BaseWatcher
    attr_reader :backends, :name, :listen, :local_port, :server_options

    def initialize(opts={}, synapse)
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

      validate_discovery_opts
    end

    def start
      log "Starting stub watcher -- this means doing nothing at all!"
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method '#{@discovery['method']}' for base watcher" \
        unless @discovery['method'] == 'base' 

      log "WARNING: a stub watcher with no default servers is pretty useless" if @default_servers.empty?
    end
  end
end
