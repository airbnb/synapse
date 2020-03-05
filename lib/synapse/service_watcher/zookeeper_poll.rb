require 'synapse/service_watcher/base'
require 'synapse/service_watcher/zookeeper'

require 'thread'
require 'zk'

class Synapse::ServiceWatcher
  class ZookeeperPollWatcher < ZookeeperWatcher

    private
    def validate_discovery_opts
      raise ArgumentError, "zookeeper poll watcher expects zookeeper_poll method" unless @discovery['method'] == 'zookeeper_poll'
    end
  end
end
