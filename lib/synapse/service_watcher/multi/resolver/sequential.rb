require 'synapse/service_watcher/multi/resolver/base'
require 'synapse/log'
require 'synapse/statsd'
require 'synapse/atomic'

class Synapse::ServiceWatcher::Resolver
  class SequentialResolver < BaseResolver
    include Synapse::Logging
    include Synapse::StatsD

    def initialize(opts, watchers, reconfigure_callback)
      @watcher_order = opts['sequential_order']
      super(opts, watchers, reconfigure_callback)

      @watcher_setting = Synapse::AtomicValue.new(@watcher_order[0])
    end

    def start
      log.info "synapse: sequential resolver: starting"
      pick_watcher
    end

    def validate_opts
      raise ArgumentError, "sequential resolver expects method to be sequential; currently: #{@opts['method']}" unless @opts['method'] == 'sequential'
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
      return current_watcher.backends
    end

    def merged_config_for_generator
      return current_watcher.config_for_generator
    end

    def healthy?
      pick_watcher
      return current_watcher.ping?
    end

    private

    def pick_watcher
      new_watcher = @watcher_order[0]

      ordered_watchers.each do |watcher_name, watcher|
        if watcher.ping? && watcher.watching? && watcher.backends != [] && watcher.config_for_generator != {}
          log.debug "synapse: sequential resolver: first healthy watcher is #{watcher_name}"
          new_watcher = watcher_name
          break
        end
      end

      unless @watcher_setting.get == new_watcher
        @watcher_setting.set(new_watcher)
        log.info "synapse: sequential resolver: picked watcher #{new_watcher}"
        statsd_increment('synapse.watcher.multi.resolver.sequential.switch', ['result:success', "watcher:#{new_watcher}"])

        send_notification
      end
    end

    def current_watcher
      watcher_name = @watcher_setting.get
      return @watchers[watcher_name]
    end

    def ordered_watchers
      @watcher_order.map { |w| [w, @watchers[w]] }
    end
  end
end
