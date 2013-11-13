require_relative './config_fetcher'

module Synapse
  class BaseDiscoverer
    attr_reader :services

    def initialize(opts={}, static_services=[], synapse)
      super()

      @synapse = synapse
      @opts = opts
      @static_services = static_services

      @services = []
      @discovered_services = []

      raise ArgumentError, "Missing config fetcher" \
        unless @opts.has_key?('fetcher')

      @config_fetcher = create_config_fetcher(opts['fetcher'])

      validate_discovery_opts
    end

    # this should be overridden to actually start your discoverer
    def start
      log.info "synapse: starting stub discoverer; this means doing nothing at all!"
    end

    # this should be overridden to do a health check of the discoverer
    def ping?
      true
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method '#{@opts['method']}' for base discoverer" \
        unless @opts['method'] == 'base'

      log.warn "synapse: warning: a stub discoverer is pretty useless"
    end

    def create_config_fetcher(opts)
      return ConfigFetcher.create(opts)
    end

    def update_service_watchers

      # Clean up dead services
      @services.each do |serviceName, watcher|
        if @discovered_services.index(serviceName).nil?
          @services.delete(serviceName)
        end
      end

      # Run through the discovered services and add any new ones
      @discovered_services.each do |serviceName|

        # Do we already know about this?
        if (not @services.key?(serviceName)) and
           @static_services.index(serviceName).nil?
          # No - we haven't seen this. Fetch the config
          begin
            cfg = @config_fetcher.fetch serviceName
            @services[serviceName] = cfg
          rescue => e
            # If something goes wrong just log it and ignore. No need to crash
            log.error "synapse: Error fetching config for service #{serviceName}:\n#{e.inspect}"
          end
        end
      end
    end
  end
end
