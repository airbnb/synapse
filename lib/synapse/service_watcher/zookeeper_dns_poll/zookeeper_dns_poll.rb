require 'synapse/service_watcher/base/base'
require 'synapse/service_watcher/zookeeper_dns/zookeeper_dns'
require 'synapse/service_watcher/zookeeper_poll/zookeeper_poll'

require 'thread'

class Synapse::ServiceWatcher
  class ZookeeperDnsPollWatcher < ZookeeperDnsWatcher
    def make_zookeeper_watcher(queue)
      zookeeper_discovery_opts = @discovery.select do |k,_|
        k == 'hosts' || k == 'path' || k == 'label_filter' || k == 'polling_interval_sec'
      end
      zookeeper_discovery_opts['method'] = 'zookeeper_poll'

      Synapse::ServiceWatcher::ZookeeperPollWatcher.new(
        mk_child_watcher_opts(zookeeper_discovery_opts),
        @synapse,
        ->(backends, *args) { update_dns_watcher(queue, backends) },
      )
    end

    def validate_discovery_opts
      unless @discovery['method'] == 'zookeeper_dns_poll'
        raise ArgumentError, "invalid discovery method #{@discovery['method']}; expecting zookeeper_dns_poll"
      end

      unless @discovery['hosts']
        raise ArgumentError, "missing or invalid zookeeper host for service #{@name}"
      end

      unless @discovery['path']
        raise ArgumentError, "invalid zookeeper path for service #{@name}"
      end
    end
  end
end
