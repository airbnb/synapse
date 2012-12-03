require_relative "./service_watcher/base"
require_relative "./service_watcher/zookeeper"

module Synapse
  class ServiceWatcher

    @watchers = {
      'base'=>BaseWatcher,
      'zookeeper'=>ZookeeperWatcher,
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
  end
end
