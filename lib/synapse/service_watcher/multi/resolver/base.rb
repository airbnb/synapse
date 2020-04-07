require "synapse/log"
require "synapse/statsd"

class Synapse::ServiceWatcher::Resolver
  class BaseResolver
    include Synapse::Logging
    include Synapse::StatsD

    def initialize(opts, watchers, notification_callback)
      super()

      log.info "creating base resolver"

      @opts = opts
      @watchers = watchers
      @notification_callback = notification_callback
      validate_opts
    end

    def validate_opts
      raise ArgumentError, "base resolver expects method to be base" unless @opts['method'] == 'base'
      raise ArgumentError, "no watchers provided" unless @watchers.length > 0
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
    def merged_backends
      return []
    end

    # should be overridden in child classes
    def merged_config_for_generator
      return {}
    end

    # should be overridden in child classes
    def healthy?
      return true
    end

    def send_notification
      @notification_callback.call
    end
  end
end
