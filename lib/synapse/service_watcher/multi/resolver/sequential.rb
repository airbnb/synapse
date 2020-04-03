require 'synapse/service_watcher/multi/resolver/base'
require 'synapse/log'
require 'synapse/statsd'

class Synapse::ServiceWatcher::Resolver
  class SequentialResolver < BaseResolver
    include Synapse::Logging
    include Synapse::StatsD

    def initialize(opts, watchers, reconfigure_callback)
      @watcher_order = opts['sequential_order']
      super(opts, watchers, reconfigure_callback)
    end

    def validate_opts
      raise ArgumentError, "sequential resolver expects method to be union" unless @opts['method'] == 'sequential'
      raise ArgumentError, "no watchers provided" unless @watchers.length > 0
      raise ArgumentError, "no sequential order defined" if @watcher_order.nil?

      watcher_names = @watchers.keys.to_set
      watcher_order_names = @watcher_order.to_set

      watcher_names.each do |watcher|
        raise ArgumentError, "sequential_order does not contain: #{watcher}" unless watcher_order_names.include?(watcher)
      end

      watcher_order_names.each do |watcher|
        raise ArgumentError, "sequential_order has unknown watcher: #{watcher}" unless watcher_names.include?(watcher)
      end
    end

    def merged_backends
      ordered_watchers.each do |w|
        backends = w.backends
        return backends unless backends == []
      end

      return []
    end

    def healthy?
      return ordered_watchers.any? { |w| w.ping? }
    end

    private

    def ordered_watchers
      return @watcher_order.map { |w| @watchers[w] }
    end
  end
end
