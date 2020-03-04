require "synapse/log"
require "synapse/statsd"

class Synapse::ServiceWatcher::Resolver
  class BaseResolver
    include Synapse::Logging
    include Synapse::StatsD

    def initialize(opts, watchers)
      super()

      log.info "creating base resolver"

      raise ArgumentError, "BaseResolver expects method to be base" unless opts['method'] == 'base'
      raise ArgumentError, "no watchers provided" unless watchers.length > 0

      @opts = opts
      @watchers = watchers
    end

    # should be overridden in child classes
    def start
      log.info "starting base resolver"
    end

    # should be overridden in child classes
    def stop
      log.info "stopping base resolver"
    end

    # should be overridden in child classes
    def backends
      return []
    end

    # should be overridden in child classes
    def ping?
      return true
    end
  end
end
