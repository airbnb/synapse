require "synapse/service_watcher/base"

require 'thread'
require 'zk'
require 'zookeeper'
require 'base64'
require 'objspace'

class Synapse::ServiceWatcher
  class ZookeeperWatcher < BaseWatcher
    NUMBERS_RE = /^\d+$/
    MIN_JITTER = 0
    MAX_JITTER = 120
    # when zk child name starts with this prefix, try to decode child name to get service discovery
    # metadata (such as ip, port, labels). If decoding failes with exception, then fallback to
    # get and parse zk child data
    CHILD_NAME_ENCODING_PREFIX = 'base64_'

    ZK_RETRIABLE_ERRORS = [
      ZK::Exceptions::OperationTimeOut,
      ZK::Exceptions::ConnectionLoss,
      ::Zookeeper::Exceptions::NotConnected,
      ::Zookeeper::Exceptions::ContinuationTimeoutError]

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

      @retry_policy = @discovery['retry_policy'] || {}
      @retry_policy['max_attempts'] = @retry_policy['max_attempts'] || 10
      @retry_policy['max_delay'] = @retry_policy['max_delay'] || 600
      @retry_policy['base_interval'] = @retry_policy['base_interval'] || 0.5
      @retry_policy['max_interval'] = @retry_policy['max_interval'] || 60
    end

    def start
      zk_host_list = @discovery['hosts'].sort
      @zk_cluster = host_list_to_cluster(zk_host_list)
      @zk_hosts = zk_host_list.join(',')

      @watcher = nil
      @zk = nil

      log.info "synapse: starting ZK watcher #{@name} @ cluster: #{@zk_cluster} path: #{@discovery['path']} retry policy: #{@retry_policy}"
      zk_connect
    end

    def stop
      log.warn "synapse: zookeeper watcher exiting"
      zk_cleanup
    end

    def ping?
      # @zk being nil implies no session *or* a lost session, do not remove
      # the check on @zk being truthy
      # if the client is in any of the three states: associating, connecting, connected
      # we consider it alive. this can avoid synapse restart on short network dis-connection
      @zk && (@zk.associating? || @zk.connecting? || @zk.connected?)
    end

    private

    def host_list_to_cluster(list)
      first_host = list.sort.first
      first_token = first_host.split('.').first
      # extract cluster name by filtering name of first host
      # remove domain extents and trailing numbers
      last_non_number = first_token.rindex(/[^0-9]/)
      last_non_number ? first_token[0..last_non_number] : first_host
    end

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
      # recurse if the parent node does not exist
      create File.dirname(path) unless @zk.exists? File.dirname(path)
      @zk.create(path, ignore: :node_exists)
    end

    # find the current backends at the discovery path
    def discover
      statsd_increment('synapse.watcher.zk.discovery', ["zk_cluster:#{@zk_cluster}", "zk_path:#{@discovery['path']}", "service_name:#{@name}"])
      statsd_time('synapse.watcher.zk.discovery.elapsed_time', ["zk_cluster:#{@zk_cluster}", "zk_path:#{@discovery['path']}", "service_name:#{@name}"]) do
        log.info "synapse: discovering backends for service #{@name}"

        new_backends = []
        zk_children = with_retry(@retry_policy.merge({'retriable_errors' => ZK_RETRIABLE_ERRORS})) do |attempts|
            statsd_time('synapse.watcher.zk.children.elapsed_time', ["zk_cluster:#{@zk_cluster}", "service_name:#{@name}"]) do
              log.debug "synapse: zk list children at #{@discovery['path']} for #{attempts} times"
              @zk.children(@discovery['path'], :watch => true)
            end
        end
        statsd_gauge('synapse.watcher.zk.children.bytes', ObjectSpace.memsize_of(zk_children), ["zk_cluster:#{@zk_cluster}", "zk_path:#{@discovery['path']}"])

        zk_children.each do |id|
          if id.start_with?(CHILD_NAME_ENCODING_PREFIX)
            decoded = parse_base64_encoded_prefix(id)
            if decoded != nil
              new_backends << create_backend_info(id, decoded)
              next
            end
          end

          begin
            node = with_retry(@retry_policy.merge({'retriable_errors' => ZK_RETRIABLE_ERRORS})) do |attempts|
              statsd_time('synapse.watcher.zk.get.elapsed_time', ["zk_cluster:#{@zk_cluster}", "service_name:#{@name}"]) do
                log.debug "synapse: zk get child at #{@discovery['path']}/#{id} for #{attempts} times"
                @zk.get("#{@discovery['path']}/#{id}")
              end
            end
          rescue ZK::Exceptions::NoNode => e
            # This can happen when the registry unregisters a service node between
            # the call to @zk.children and @zk.get(path). ZK does not guarantee
            # a read to ``get`` of a child returned by ``children`` will succeed
            log.error("synapse: #{@discovery['path']}/#{id} disappeared before it could be read: #{e}")
            next
          rescue StandardError => e
            log.error("synapse: #{@discovery['path']}/#{id} failed to get from ZK: #{e}")
            statsd_increment('synapse.watcher.zk.get_child_failed')
            raise e
          end

          begin
            # TODO: Do less munging, or refactor out this processing
            decoded = deserialize_service_instance(node.first)
          rescue StandardError => e
            log.error "synapse: skip child due to invalid data in ZK at #{@discovery['path']}/#{id}: #{e}"
            statsd_increment('synapse.watcher.zk.parse_child_failed')
          else
            new_backends << create_backend_info(id, decoded)
          end
        end

        # support for a separate 'generator_config_path' key, for reading the
        # generator config block, that may be different from the 'path' key where
        # we discover service instances. if generator_config_path is present and
        # the value is "disabled", then skip all zk-based discovery of the
        # generator config (and use the values from the local config.json
        # instead).
        case @discovery.fetch('generator_config_path', nil)
        when 'disabled'
          discovery_key = nil
        when nil
          discovery_key = 'path'
        else
          discovery_key = 'generator_config_path'
        end

        if discovery_key
          begin
            node = with_retry(@retry_policy.merge({'retriable_errors' => ZK_RETRIABLE_ERRORS})) do |attempts|
                statsd_time('synapse.watcher.zk.get.elapsed_time', ["zk_cluster:#{@zk_cluster}", "service_name:#{@name}"]) do
                  log.debug "synapse: zk get parent at #{@discovery[discovery_key]} for #{attempts} times"
                  @zk.get(@discovery[discovery_key], :watch => true)
                end
            end
            new_config_for_generator = parse_service_config(node.first)
          rescue ZK::Exceptions::NoNode => e
            log.error "synapse: No ZK node for config data at #{@discovery[discovery_key]}: #{e}"
            new_config_for_generator = {}
          rescue StandardError => e
            log.error "synapse: skip path due to invalid data in ZK at #{@discovery[discovery_key]}: #{e}"
            statsd_increment('synapse.watcher.zk.get_config_failed')
            new_config_for_generator = {}
          end
        else
          new_config_for_generator = {}
        end

        set_backends(new_backends, new_config_for_generator)
      end
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      return if @zk.nil?
      log.debug "synapse: setting watch at #{@discovery['path']}"

      statsd_time('synapse.watcher.zk.watch.elapsed_time', ["zk_cluster:#{@zk_cluster}", "zk_path:#{@discovery['path']}", "service_name:#{@name}"]) do
        unless @watcher
          log.debug "synapse: zk register at #{@discovery['path']}"
          @watcher = @zk.register(@discovery['path'], &watcher_callback)
        end

        # Verify that we actually set up the watcher.
        existed = with_retry(@retry_policy.merge({'retriable_errors' => ZK_RETRIABLE_ERRORS})) do |attempts|
          log.debug "synapse: zk exists at #{@discovery['path']} for #{attempts} times"
          @zk.exists?(@discovery['path'], :watch => true)
        end
        unless existed
          log.error "synapse: zookeeper watcher path #{@discovery['path']} does not exist!"
          statsd_increment('synapse.watcher.zk.register_failed')
          zk_cleanup
        end
      end
      log.debug "synapse: set watch for parent at #{@discovery['path']}"
    end

    # handles the event that a watched path has changed in zookeeper
    def watcher_callback
      @callback ||= Proc.new do |event|
        # We instantiate ZK client with :thread => :per_callback
        # https://github.com/zk-ruby/zk/wiki/EventDeliveryModel#thread-per-callback
        # Only one thread will be executing the callback at a time
        #
        # We call watch on every callback, but do not call zk.register => change callback, except the first time.
        #
        # We sleep if we have not slept in discovery_jitter seconds
        # We loose / do not get any events during this time for this service.
        # This helps with throttling discover.
        #
        # We call watch and discover on every callback.
        # We call exists(watch), children(discover) and get(discover) with (:watch=>true)
        # This re-initializes callbacks just before get scan. So we do not miss any updates by sleeping.
        #
        if @discovery['discovery_jitter']
          if @discovery['discovery_jitter'].between?(MIN_JITTER, MAX_JITTER)
            if @last_discovery && (Time.now - @last_discovery) < @discovery['discovery_jitter']
              log.info "synapse: sleeping for discovery_jitter=#{@discovery['discovery_jitter']} seconds for service:#{@name}"
              sleep @discovery['discovery_jitter']
            end
            @last_discovery = Time.now
          else
            log.warn "synapse: invalid discovery_jitter=#{@discovery['discovery_jitter']} for service:#{@name}"
          end
        end
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
      statsd_time('synapse.watcher.zk.connect.elapsed_time', ["zk_cluster:#{@zk_cluster}", "service_name:#{@name}"]) do
        log.info "synapse: zookeeper watcher connecting to ZK at #{@zk_hosts}"

        # Ensure that all Zookeeper watcher re-use a single zookeeper
        # connection to any given set of zk hosts.
        @@zk_pool_lock.synchronize {
          unless @@zk_pool.has_key?(@zk_hosts)
            # connecting to zookeeper could runtime error under certain network failure
            # https://github.com/zk-ruby/zookeeper/blob/80a88e3179fd1d526f7e62a364ab5760f5f5da12/ext/zkrb.c
            @@zk_pool[@zk_hosts] = with_retry(@retry_policy.merge({'retriable_errors' => RuntimeError})) do |attempts|
                log.info "synapse: creating pooled connection to #{@zk_hosts} for #{attempts} times"
                ZK.new(@zk_hosts, :timeout => 5, :thread => :per_callback)
            end
            @@zk_pool_count[@zk_hosts] = 1
            log.info "synapse: successfully created zk connection to #{@zk_hosts}"
            statsd_increment('synapse.watcher.zk.client.created', ["zk_cluster:#{@zk_cluster}", "service_name:#{@name}"])
          else
            @@zk_pool_count[@zk_hosts] += 1
            log.info "synapse: re-using existing zookeeper connection to #{@zk_hosts}"
            statsd_increment('synapse.watcher.zk.client.reused', ["zk_cluster:#{@zk_cluster}", "service_name:#{@name}"])
          end
        }

        @zk = @@zk_pool[@zk_hosts]
        log.info "synapse: retrieved zk connection to #{@zk_hosts}"

        # handle session expiry -- by cleaning up zk, this will make `ping?`
        # fail and so synapse will exit
        @zk.on_expired_session do
          statsd_increment('synapse.watcher.zk.session.expired', ["zk_cluster:#{@zk_cluster}", "service_name:#{@name}"])
          log.warn "synapse: ZK client session expired #{@name}"
          zk_cleanup
        end

        # the path must exist, otherwise watch callbacks will not work
        with_retry(@retry_policy.merge({'retriable_errors' => ZK_RETRIABLE_ERRORS})) do |attempts|
          statsd_time('synapse.watcher.zk.create_path.elapsed_time', ["zk_cluster:#{@zk_cluster}", "service_name:#{@name}"]) do
            log.debug "synapse: zk create at #{@discovery['path']} for #{attempts} times"
            create(@discovery['path'])
          end
        end
        # call the callback to bootstrap the process
        watcher_callback.call
      end
    end

    # decode the data at a zookeeper endpoint
    def deserialize_service_instance(data)
      log.debug "synapse: deserializing process data"
      decoded = @decode_method.call(data)

      unless decoded.key?('host')
        raise KeyError, 'instance json data does not have host key'
      end

      unless decoded.key?('port')
        raise KeyError, 'instance json data does not have port key'
      end

      return decoded
    end

    # find the encoded metadata in the prefix of child name; used for path encoding if enabled
    def parse_base64_encoded_prefix(child_name)
      child_name = child_name.sub(CHILD_NAME_ENCODING_PREFIX, '')
      length_str = child_name[/\d+_/]
      length = length_str[0..-1].to_i
      child_name = child_name.sub(length_str, '')
      child_name = child_name[0..length-1]
      JSON.parse(Base64.urlsafe_decode64(child_name))
    rescue StandardError => e
      log.error("synapse: parse base64 encoded prefix failed for #{child_name}: #{e}")
      nil
    end

    # find the numberic id in suffix of child name; used for leader elections if enabled
    def parse_numeric_id_suffix(child_name)
      numeric_id = child_name.split('_').last
      numeric_id = NUMBERS_RE =~ numeric_id ? numeric_id.to_i : nil
    end

    def parse_service_config(data)
      log.debug "synapse: deserializing process data"
      if data.nil? || data.empty?
        decoded = {}
      else
        decoded = @decode_method.call(data)
      end

      new_generator_config = {}
      # validate the config. if the config is not empty:
      #   each key should be named by one of the available generators
      #   each value should be a hash (could be empty)
      decoded.collect.each do |generator_name, generator_config|
        if !@synapse.available_generators.keys.include?(generator_name)
          log.warn "synapse: invalid generator name in ZK node at #{@discovery['path']}:" \
            " #{generator_name}"
          next
        else
          if generator_config.nil? || !generator_config.is_a?(Hash)
            log.warn "synapse: invalid generator config in ZK node at #{@discovery['path']}" \
              " for generator #{generator_name}"
            new_generator_config[generator_name] = {}
          else
            new_generator_config[generator_name] = generator_config
          end
        end
      end

      return new_generator_config
    end

    def create_backend_info(id, node)
      log.debug "synapse: discovered backend with child #{id} at #{node['host']}:#{node['port']} for service #{@name}"
      node['id'] = parse_numeric_id_suffix(id)
      return {
        'name' => node['name'], 'host' => node['host'], 'port' => node['port'],
        'id' => node['id'], 'weight' => node['weight'],
        'haproxy_server_options' => node['haproxy_server_options'],
        'labels' => node['labels']
      }
    end
  end
end

