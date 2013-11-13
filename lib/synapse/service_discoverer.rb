require_relative "./service_discoverer/base"
require_relative "./service_discoverer/zookeeper"

module Synapse
  class ServiceDiscoverer

    @discoverers = {
      'base'=>BaseDiscoverer,
      'zookeeper'=>ZookeeperDiscoverer,
    }

    # the method which actually dispatches watcher creation requests
    def self.create(opts={}, static_services=[], synapse)
      raise ArgumentError, "Missing discovery method when trying to create discoverer" \
        unless opts.key?('method')

      discovery_method = opts['method']
      raise ArgumentError, "Invalid discovery method #{discovery_method}" \
        unless @discoverers.key?(discovery_method)

      return @discoverers[discovery_method].new(opts, static_services, synapse)
    end
  end
end
