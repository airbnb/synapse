# encoding: utf-8
#
# Variant of the Zookeeper service watcher that works with Apache Aurora
# service announcements.
#
# Parameters:
#   hosts: list of zookeeper hosts to query (List of Strings, required)
#   path: "/path/to/serverset/in/zookeeper" (String, required)
#   port_name: Named service endpoint (String, optional)
#
# If port_name is omitted, uses the default serviceEndpoint port.

# zk node data looks like this:
#
# {
#   "additionalEndpoints": {
#     "aurora": {
#       "host": "somehostname",
#       "port": 31943
#     },
#     "http": {
#       "host": "somehostname",
#       "port": 31943
#     },
#     "otherport": {
#       "host": "somehostname",
#       "port": 31944
#     }
#   },
#   "serviceEndpoint": {
#     "host": "somehostname",
#     "port": 31943
#   },
#   "shard": 0,
#   "status": "ALIVE"
# }
#

require 'synapse/service_watcher/zookeeper'

module Synapse
  # Watcher for Zookeeper announcements from Apache Aurora
  class ZookeeperAuroraWatcher < Synapse::ZookeeperWatcher
    def validate_discovery_opts
      @discovery['method'] == 'zookeeper_aurora' ||
        fail(ArgumentError,
             "Invalid discovery method: #{@discovery['method']}")
      @discovery['hosts'] ||
        fail(ArgumentError,
             "Missing or invalid zookeeper host for service #{@name}")
      @discovery['path'] ||
        fail(ArgumentError, "Invalid zookeeper path for service #{@name}")
    end

    def deserialize_service_instance(data)
      log.debug 'Deserializing process data'
      decoded = JSON.parse(data)

      name = decoded['shard'].to_s ||
        fail("Instance JSON data missing 'shard' key")

      hostport = if @discovery['port_name']
                   decoded['additionalEndpoints'][@discovery['port_name']] ||
                     fail("Endpoint '#{@discovery['port_name']}' not found " \
                          'in instance JSON data')
                 else
                   decoded['serviceEndpoint']
                 end

      host = hostport['host'] || fail("Instance JSON data missing 'host' key")
      port = hostport['port'] || fail("Instance JSON data missing 'port' key")

      [host, port, name]
    end
  end
end
