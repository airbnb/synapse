require "synapse/service_watcher/base"

require 'thread'
require 'zk'

class Synapse::ServiceWatcher
  class ZookeeperWatcher < BaseWatcher
    NUMBERS_RE = /^\d+$/

    @@zk_pool = {}
    @@zk_pool_count = {}
    @@zk_pool_lock = Mutex.new

    def start
      @zk_hosts = @discovery['hosts'].sort.join(',')

      @watcher = nil
      @zk = nil

      log.info "synapse: starting ZK watcher #{@name} @ hosts: #{@zk_hosts}, path: #{@discovery['path']}"
      zk_connect
    end

    def stop
      log.warn "synapse: zookeeper watcher exiting"
      zk_cleanup
    end

    def ping?
      # @zk being nil implies no session *or* a lost session, do not remove
      # the check on @zk being truthy
      @zk && @zk.connected?
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

    # find the current backends at the discovery path
    def discover
      log.info "synapse: discovering backends for service #{@name}"

      new_backends = []
      @zk.children(@discovery['path'], :watch => true).each do |id|
        node = @zk.get("#{@discovery['path']}/#{id}")

        begin
          host, port, name, weight = deserialize_service_instance(node.first)
        rescue StandardError => e
          log.error "synapse: invalid data in ZK node #{id} at #{@discovery['path']}: #{e}"
        else
          server_port = @server_port_override ? @server_port_override : port

          # find the numberic id in the node name; used for leader elections if enabled
          numeric_id = id.split('_').last
          numeric_id = NUMBERS_RE =~ numeric_id ? numeric_id.to_i : nil

          log.debug "synapse: discovered backend #{name} at #{host}:#{server_port} for service #{@name}"
          new_backends << { 'name' => name, 'host' => host, 'port' => server_port, 'id' => numeric_id, 'weight' => weight }
        end
      end

      set_backends(new_backends)
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      return if @zk.nil?
      log.debug "synapse: setting watch at #{@discovery['path']}"

      @watcher.unsubscribe unless @watcher.nil?
      @watcher = @zk.register(@discovery['path'], &watcher_callback)

      # Verify that we actually set up the watcher.
      unless @zk.exists?(@discovery['path'], :watch => true)
        log.error "synapse: zookeeper watcher path #{@discovery['path']} does not exist!"
        raise RuntimeError.new('could not set a ZK watch on a node that should exist')
      end
      log.debug "synapse: set watch at #{@discovery['path']}"
    end

    # handles the event that a watched path has changed in zookeeper
    def watcher_callback
      @callback ||= Proc.new do |event|
        # Set new watcher
        watch
        # Rediscover
        discover
      end
    end

    def zk_cleanup
      log.info "synapse: zookeeper watcher cleaning up"

      begin
        @watcher.unsubscribe unless @watcher.nil?
        @watcher = nil
      ensure
        @@zk_pool_lock.synchronize {
          if @@zk_pool.has_key?(@zk_hosts)
            @@zk_pool_count[@zk_hosts] -= 1
            # Last thread to use the connection closes it
            if @@zk_pool_count[@zk_hosts] == 0
              log.info "synapse: closing zk connection to #{@zk_hosts}"
              begin
                @zk.close! unless @zk.nil?
              ensure
                @@zk_pool.delete(@zk_hosts)
              end
            end
          end
          @zk = nil
        }
      end

      log.info "synapse: zookeeper watcher cleaned up successfully"
    end

    def zk_connect
      log.info "synapse: zookeeper watcher connecting to ZK at #{@zk_hosts}"

      # Ensure that all Zookeeper watcher re-use a single zookeeper
      # connection to any given set of zk hosts.
      @@zk_pool_lock.synchronize {
        unless @@zk_pool.has_key?(@zk_hosts)
          log.info "synapse: creating pooled connection to #{@zk_hosts}"
          @@zk_pool[@zk_hosts] = ZK.new(@zk_hosts, :timeout => 5, :thread => :per_callback)
          @@zk_pool_count[@zk_hosts] = 1
          log.info "synapse: successfully created zk connection to #{@zk_hosts}"
        else
          @@zk_pool_count[@zk_hosts] += 1
          log.info "synapse: re-using existing zookeeper connection to #{@zk_hosts}"
        end
      }

      @zk = @@zk_pool[@zk_hosts]
      log.info "synapse: retrieved zk connection to #{@zk_hosts}"

      # handle session expiry -- by cleaning up zk, this will make `ping?`
      # fail and so synapse will exit
      @zk.on_expired_session do
        log.warn "synapse: zookeeper watcher ZK session expired!"
        zk_cleanup
      end

      # the path must exist, otherwise watch callbacks will not work
      create(@discovery['path'])

      # call the callback to bootstrap the process
      watcher_callback.call
    end

    # decode the data at a zookeeper endpoint
    def deserialize_service_instance(data)
      log.debug "synapse: deserializing process data"
      decoded = JSON.parse(data)

      host = decoded['host'] || (raise ValueError, 'instance json data does not have host key')
      port = decoded['port'] || (raise ValueError, 'instance json data does not have port key')
      name = decoded['name'] || nil
      weight = decoded['weight'] || nil

      return host, port, name, weight
    end
  end
end
