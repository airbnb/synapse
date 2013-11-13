module Synapse
  class BaseFetcher
    def initialize(opts={})
      @opts = opts

      validate_fetcher_opts
    end

    def fetch(service)
      log.warn "synapse: stub fetcher fetching - doing nothing!"
    end

    private
    def validate_fetcher_opts
      raise ArgumentError, "invalid method '#{@opts['method']}' for base fetcher" \
        unless @opts['method'] == 'base'

      log.warn "synapse: warning: a stub fetcher is pretty useless"
    end

    def apply_default_fields(config, service)
      # If we don't have a discovery method but a default one is passed in the opts then
      # add it
      if (!config.key?('discovery')) and @opts.key?('default_discovery')
        config['discovery'] = @opts['default_discovery']

        # We may need to replace the service name in the path (if there is a path)
        if config['discovery'].key?('path')
          config['discovery']['path'] = config['discovery']['path'].sub('%SERVICE_NAME%', service)
        end
      end
    end
  end
end