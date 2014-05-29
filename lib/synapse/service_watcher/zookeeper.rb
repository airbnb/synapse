require "synapse/service_watcher/base"

require 'zk'

module Synapse
  class ZookeeperWatcher < BaseWatcher
    NUMBERS_RE = /^\d+$/

    def start
      @zk_hosts = @discovery['hosts'].shuffle.join(',')

      log.info "synapse: starting ZK watcher #{@name} @ hosts: #{@zk_hosts}, path: #{@discovery['path']}"
      @should_exit = false
      @watcher = nil
      @reconnecting = false
      zk_connect
    end

    def stop
      log.warn "synapse: zookeeper watcher exiting"

      @should_exit = true
      @watcher.unsubscribe unless @watcher.nil?
      @watcher = nil
      @zk.close! unless !defined?(@zk) || !@zk.nil?

      log.info "synapse: zookeeper watcher cleaned up successfully"
    end

    def zk_connect
      @watcher.unsubscribe unless @watcher.nil?
      @watcher = nil

      log.info "synapse: connecting to ZK at #{@zk_hosts}"
      @zk.close! unless !defined?(@zk) || !@zk.nil?
      @zk = ZK.new(@zk_hosts)

      @zk.on_expired_session do
        @reconnecting = true
        log.info "synapse: ZK session expired for path: #{@discovery['path']}"
        zk_connect
        @reconnecting = false
      end

      # call the callback to bootstrap the process
      watcher_callback.call
    end

    def ping?
      @reconnecting || @zk.connected?
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

            # find the numberic id in the node name; used for leader elections if enabled
            numeric_id = id.split('_').last
            numeric_id = NUMBERS_RE =~ numeric_id ? numeric_id.to_i : nil

            log.debug "synapse: discovered backend #{name} at #{host}:#{server_port} for service #{@name}"
            new_backends << { 'name' => name, 'host' => host, 'port' => server_port, 'id' => numeric_id}
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
        set_backends(new_backends)
      end
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      return if @should_exit

      @watcher.unsubscribe unless @watcher.nil?
      @watcher = @zk.register(@discovery['path'], &watcher_callback)

      # Verify that we actually set up the watcher.
      unless @zk.exists?(@discovery['path'], :watch => true)
        log.warn "synapse: failed to create watcher at #{@discovery['path']}"
        zk_connect
      end
    end

    # handles the event that a watched path has changed in zookeeper
    def watcher_callback
      @callback ||= Proc.new do |event|
        # Set new watcher
        watch
        # Rediscover
        discover
        # send a message to calling class to reconfigure
        reconfigure!
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
