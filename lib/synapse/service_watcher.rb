require "synapse/service_watcher/base"
require "synapse/service_watcher/zookeeper"
require "synapse/service_watcher/ec2tag"
require "synapse/service_watcher/dns"
require "synapse/service_watcher/docker"

module Synapse
  class ServiceWatcher

    @watchers = {
      'base'=>BaseWatcher,
      'zookeeper'=>ZookeeperWatcher,
      'ec2tag'=>EC2Watcher,
      'dns' => DnsWatcher,
      'docker' => DockerWatcher
    }

    # allow users to extend watchers without hacking core
    def self.add_service_watcher(key, klass)
      @watchers[key] = klass
    end

    # the method which actually dispatches watcher creation requests
    def self.create(name, opts, synapse)
      opts['name'] = name

      raise ArgumentError, "Missing discovery method when trying to create watcher" \
        unless opts.has_key?('discovery') && opts['discovery'].has_key?('method')

      discovery_method = opts['discovery']['method']

      unless @watchers.has_key?(discovery_method)
        m = opts['discovery']['module'] ? opts['discovery']['module'] : "synapse-watcher-#{discovery_method}"
        require m
      end

      raise ArgumentError, "Invalid discovery method #{discovery_method}" \
        unless @watchers.has_key?(discovery_method)

      return @watchers[discovery_method].new(opts, synapse)
    end
  end
end
