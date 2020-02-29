require "synapse/service_watcher/base"

class Synapse::ServiceWatcher
  # MultiWatcher allows using multiple watchers to obtain service discovery data
  # with a configurable resolution strategy among them.
  #
  # Discovery options:
  #   method => 'multi'
  #   watchers => hash. Maps name => discovery hash. Discovery hash must include
  #     method, and be of the same format as the method type expects.
  #     (That is, method => zookeeper means a Zookeeper watcher will be created, so
  #     the rest of the options will be passed to the ZookeeperWatcher class).
  class MultiWatcher < BaseWatcher
    # Resolves the discovery and discovery_multi configuration into a single
    # hash that can be passed to this class.
    def self.merge_discovery(discovery_multi, discovery)
      # deep clone the object first
      opts = Marshal.load(Marshal.dump(discovery_multi))
      opts['method'] = 'multi' unless opts.has_key?('method')
      opts['watchers'] ||= {}

      raise ArgumentError, "multi watcher config already has primary watcher defined" if opts['watchers'].has_key?('primary')
      opts['watchers']['primary'] = discovery

      return opts
    end

    def initialize(opts={}, reconfigure_callback=nil, synapse)
      super(opts, reconfigure_callback, synapse)

      @watchers = {}

      watcher_config = @discovery['watchers'] || {}

      watcher_config.each do |name, config|
        # Merge (deep-cloned) top-level config with the discovery configuration.
        merged_config = Marshal.load(Marshal.dump(opts))
        merged_config['discovery'] = config

        unless config.is_a?(Hash)
          raise ArgumentError, "Child watcher is not a hash for watcher #{name}"
        end

        unless config.has_key?('method')
          raise ArgumentError, "Discovery method not included in config for watcher #{name}"
        end

        discovery_method = config['method']
        watcher = Synapse::ServiceWatcher.load_watcher(discovery_method, merged_config, synapse)

        @watchers[name] = watcher
      end
    end

    def start
      log.info "synapse: starting multi watcher"

      @watchers.values.each do |w|
        w.start
      end
    end

    def stop
      log.warn "synapse: multi watcher exiting"

      @watchers.values.each do |w|
        w.stop
      end
    end

    def ping?
      @watchers.values.all? do |w|
        w.ping?
      end
    end

    private

    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method '#{@discovery['method']}' for multi watcher" \
        unless @discovery['method'] == 'multi'

      raise ArgumentError, "watcher config is empty" if @discovery['watchers'].empty?
    end
  end
end
