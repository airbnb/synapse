require 'synapse/service_watcher/multi/resolver/base'
require 'synapse/log'
require 'synapse/statsd'

class Synapse::ServiceWatcher::Resolver
  class UnionResolver < BaseResolver
    include Synapse::Logging
    include Synapse::StatsD

    def validate_opts
      raise ArgumentError, "union resolver expects method to be union" unless @opts['method'] == 'union'
      raise ArgumentError, "no watchers provided" unless @watchers.length > 0
    end

    def merged_backends
      return @watchers.values.map { |w| w.backends }.flatten
    end

    def merged_config_for_generator
      return @watchers
        .values
        .map { |w| w.config_for_generator }
        .select { |c| !c.empty? }
        .first || {}
    end

    def healthy?
      return @watchers.values.any? { |w| w.ping? }
    end
  end
end
