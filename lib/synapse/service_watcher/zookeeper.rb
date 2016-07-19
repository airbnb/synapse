require "synapse/service_watcher/base"

require 'thread'
require 'zk'

class Synapse::ServiceWatcher
  class ZookeeperWatcher < BaseWatcher
    NUMBERS_RE = /^\d+$/

    @@zk_pool = {}
    @@zk_pool_count = {}
    @@zk_pool_lock = Mutex.new

    def initialize(opts={}, synapse)
      super(opts, synapse)

      # Alternative deserialization support. By default we use nerve
      # deserialization, but we also support serverset registries
      @decode_method = self.method(:nerve_decode)
      if @discovery['decode']
        valid_methods = ['nerve', 'serverset']
        decode_method = @discovery['decode']['method']
        unless decode_method && valid_methods.include?(decode_method)
          raise ArgumentError, "missing or invalid decode method #{decode_method}"
        end
        if decode_method == 'serverset'
          @decode_method = self.method(:serverset_decode)
        end
      end
    end

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

    # Supported decode methods

    # Airbnb nerve ZK node data looks like this:
    #
    # {
    #   "host": "somehostname",
    #   "port": 1234,
    # }
    def nerve_decode(data)
      JSON.parse(data)
    end

    # Twitter serverset ZK node data looks like this:
    #
    # {
    #   "additionalEndpoints": {
    #     "serverset": {
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
    def serverset_decode(data)
      decoded = JSON.parse(data)
      if @discovery['decode']['endpoint_name']
        endpoint_name = @discovery['decode']['endpoint_name']
        raise KeyError, "json data has no additionalEndpoint called #{endpoint_name}" \
          unless decoded['additionalEndpoints'] && decoded['additionalEndpoints'][endpoint_name]
        result = decoded['additionalEndpoints'][endpoint_name]
      else
        result = decoded['serviceEndpoint']
      end
      result['name'] = decoded['shard'] || nil
      result['name'] = result['name'].to_s unless result['name'].nil?
      result
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
        begin
          node = @zk.get("#{@discovery['path']}/#{id}")
        rescue ZK::Exceptions::NoNode => e
          # This can happen when the registry unregisters a service node between
          # the call to @zk.children and @zk.get(path). ZK does not guarantee
          # a read to ``get`` of a child returned by ``children`` will succeed
          log.error("synapse: #{@discovery['path']}/#{id} disappeared before it could be read: #{e}")
          next
        end

        begin
          # TODO: Do less munging, or refactor out this processing
          host, port, name, weight, haproxy_server_options, labels = deserialize_service_instance(node.first)
        rescue StandardError => e
          log.error "synapse: invalid data in ZK node #{id} at #{@discovery['path']}: #{e}"
        else
          # find the numberic id in the node name; used for leader elections if enabled
          numeric_id = id.split('_').last
          numeric_id = NUMBERS_RE =~ numeric_id ? numeric_id.to_i : nil

          log.debug "synapse: discovered backend #{name} at #{host}:#{port} for service #{@name}"
          new_backends << {
            'name' => name, 'host' => host, 'port' => port,
            'id' => numeric_id, 'weight' => weight,
            'haproxy_server_options' => haproxy_server_options,
            'labels' => labels
          }
        end
      end

      set_backends(new_backends)
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      return if @zk.nil?
      log.debug "synapse: setting watch at #{@discovery['path']}"

      @watcher = @zk.register(@discovery['path'], &watcher_callback) unless @watcher

      # Verify that we actually set up the watcher.
      unless @zk.exists?(@discovery['path'], :watch => true)
        log.error "synapse: zookeeper watcher path #{@discovery['path']} does not exist!"
        zk_cleanup
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
      decoded = @decode_method.call(data)

      host = decoded['host'] || (raise KeyError, 'instance json data does not have host key')
      port = decoded['port'] || (raise KeyError, 'instance json data does not have port key')
      name = decoded['name'] || nil
      weight = decoded['weight'] || nil
      haproxy_server_options = decoded['haproxy_server_options'] || nil
      labels = decoded['labels'] || nil

      return host, port, name, weight, haproxy_server_options, labels
    end
  end
end

