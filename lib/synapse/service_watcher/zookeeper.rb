require "synapse/service_watcher/base"

require 'zk'

module Synapse
  class ZookeeperWatcher < BaseWatcher
    def start
      zk_hosts = @discovery['hosts'].shuffle.join(',')

      log.info "synapse: starting ZK watcher #{@name} @ hosts: #{zk_hosts}, path: #{@discovery['path']}"
      @should_exit = false
      @zk = ZK.new(zk_hosts)

      # call the callback to bootstrap the process
      watcher_callback.call
    end

    def stop
      log.warn "synapse: zookeeper watcher exiting"

      @should_exit = true
      @watcher.unsubscribe if defined? @watcher
      @zk.close! if defined? @zk

      log.info "synapse: zookeeper watcher cleaned up successfully"
    end

    def ping?
      @zk.ping?
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'zookeeper'
      raise ArgumentError, "missing or invalid zookeeper host for service #{@name}" \
        unless @discovery['hosts']
      raise ArgumentError, "invalid zookeeper path for service #{@name}" \
        unless @discovery['path']
    end

    # helper method that ensures that the discovery path exists
    def create(path)
      log.debug "synapse: creating ZK path: #{path}"
      # recurse if the parent node does not exist
      create File.dirname(path) unless @zk.exists? File.dirname(path)
      @zk.create(path, ignore: :node_exists)
    end

    # find the current backends at the discovery path; sets @backends
    def discover
      log.info "synapse: discovering backends for service #{@name}"

      new_backends = []
      begin
        @zk.children(@discovery['path'], :watch => true).each do |id|
          node = @zk.get("#{@discovery['path']}/#{id}")

          begin
            host, port, name = deserialize_service_instance(node.first)
          rescue StandardError => e
            log.error "synapse: invalid data in ZK node #{id} at #{@discovery['path']}: #{e}"
          else
            server_port = @server_port_override ? @server_port_override : port

            log.debug "synapse: discovered backend #{name} at #{host}:#{server_port} for service #{@name}"
            new_backends << { 'name' => name, 'host' => host, 'port' => server_port, 'id' => id}
          end
        end
      rescue ZK::Exceptions::NoNode
        # the path must exist, otherwise watch callbacks will not work
        create(@discovery['path'])
        retry
      end

      if new_backends.empty?
        if @default_servers.empty?
          log.warn "synapse: no backends and no default servers for service #{@name}; using previous backends: #{@backends.inspect}"
        else
          log.warn "synapse: no backends for service #{@name}; using default servers: #{@default_servers.inspect}"
          @backends = @default_servers
        end
      else
        log.info "synapse: discovered #{new_backends.length} backends for service #{@name}"
        @backends = new_backends
      end
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      return if @should_exit

      @watcher.unsubscribe if defined? @watcher
      @watcher = @zk.register(@discovery['path'], &watcher_callback)
    end

    # handles the event that a watched path has changed in zookeeper
    def watcher_callback
      @callback ||= Proc.new do |event|
        # Set new watcher
        watch
        # Rediscover
        discover
        # send a message to calling class to reconfigure
        @synapse.reconfigure!
      end
    end

    # decode the data at a zookeeper endpoint
    def deserialize_service_instance(data)
      log.debug "synapse: deserializing process data"
      decoded = JSON.parse(data)

      host = decoded['host'] || (raise ValueError, 'instance json data does not have host key')
      port = decoded['port'] || (raise ValueError, 'instance json data does not have port key')
      name = decoded['name'] || nil

      return host, port, name
    end
  end
end
