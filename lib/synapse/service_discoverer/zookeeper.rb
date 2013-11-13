require_relative "./base"

require 'zk'

module Synapse
  class ZookeeperDiscoverer < BaseDiscoverer

    def start

      @services = {}

      zk_hosts = @opts['hosts'].shuffle.join(',')

      log.info "synapse: starting ZK discoverer @ hosts: #{zk_hosts}, path: #{@opts['path']}"

      @zk = ZK.new(zk_hosts)

      # call the callback to bootstrap the process
      watcher_callback.call
    end

    def ping?
      @zk.ping?
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@opts['method']}" \
        unless @opts['method'] == 'zookeeper'
      raise ArgumentError, "missing or invalid zookeeper host for zookeeper service discoverer" \
        unless @opts['hosts']
      raise ArgumentError, "invalid zookeeper path for zookeeper service discoverer" \
        unless @opts['path']
    end

    # helper method that ensures that the discovery path exists
    def create(path)
      log.debug "synapse: creating ZK path: #{path}"
      # recurse if the parent node does not exist
      create File.dirname(path) unless @zk.exists? File.dirname(path)
      @zk.create(path, ignore: :node_exists)
    end

    # find the current services at the discovery path; sets @services
    def discover
      log.info "synapse: discovering services via zookeeperat #{@opts['path']}"

      @discovered_services = []

      begin
        @zk.children(@opts['path'], :watch => true).map do |name|
          log.debug "synapse: discovered service #{name}"
          @discovered_services << name
        end
      rescue ZK::Exceptions::NoNode
        # the path must exist, otherwise watch callbacks will not work
        create(@opts['path'])
        retry
      end
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      @watcher.unsubscribe if defined? @watcher
      @watcher = @zk.register(@opts['path'], &watcher_callback)
    end

    # handles the event that a watched path has changed in zookeeper
    def watcher_callback
      @callback ||= Proc.new do |event|
        # Set new watcher
        watch
        # Rediscover
        discover
        # Update watchers
        update_service_watchers
        # send a message to calling class to reconfigure
        @synapse.reconfigure!
      end
    end
  end
end
