require_relative "./service_watcher/base"
require_relative "./service_watcher/zookeeper"
require_relative "./service_watcher/ec2tag"

module Synapse
  class ServiceWatcher

    @watchers = {
      'base'=>BaseWatcher,
      'zookeeper'=>ZookeeperWatcher,
      'ec2tag'=>EC2Watcher,
    }

    # the method which actually dispatches watcher creation requests
    def self.create(opts, synapse)
      raise ArgumentError, "Missing discovery method when trying to create watcher" \
        unless opts.has_key?('discovery') && opts['discovery'].has_key?('method')

      discovery_method = opts['discovery']['method']
      raise ArgumentError, "Invalid discovery method #{discovery_method}" \
        unless @watchers.has_key?(discovery_method)

      return @watchers[discovery_method].new(opts, synapse)
    end
  end
end
