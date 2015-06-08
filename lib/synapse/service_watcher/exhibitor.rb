require "synapse/service_watcher/base"

require 'zk'

module Synapse
  class ExhibitorWatcher < BaseWatcher
    NUMBERS_RE = /^\d+$/

    def start
      @exhibitor_url = @discovery['exhibitor_url']
      @zk_hosts = fetch_hosts_from_exhibitor

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
      new_zk_hosts = fetch_hosts_from_exhibitor
      if new_zk_hosts and @zk_hosts != new_zk_hosts
        log.info "synapse: ZooKeeper ensamble changed, going to reconnect"
        @zk_hosts = new_zk_hosts
        stop
        start
      end
      @zk && @zk.connected?
    end

    private

    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'exhibitor'
      raise ArgumentError, "missing or invalid exhibitor url for service #{@name}" \
        unless @discovery['exhibitor_url']
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

    def fetch_hosts_from_exhibitor
      uri = URI(@exhibitor_url)
      req = Net::HTTP::Get.new(uri)
      if @discovery['exhibitor_user'] and @discovery['exhibitor_password']
        req.basic_auth(@discovery['exhibitor_user'], @discovery['exhibitor_password'])
      end
      res = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(req)
      end

      if res.code.to_i != 200
        raise "Something went wrong: #{res.body}"
      end
      hosts = JSON.load(res.body)
      log.info hosts
      zk_hosts = hosts['servers'].map { |s| s.concat(':' + hosts['port'].to_s) }
      zk_hosts.sort.join(',')
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      return if @zk.nil?

      @watcher.unsubscribe unless @watcher.nil?
      @watcher = @zk.register(@discovery['path'], &watcher_callback)

      # Verify that we actually set up the watcher.
      unless @zk.exists?(@discovery['path'], :watch => true)
        log.error "synapse: zookeeper watcher path #{@discovery['path']} does not exist!"
        raise RuntimeError.new('could not set a ZK watch on a node that should exist')
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

    def zk_cleanup
      log.info "synapse: zookeeper watcher cleaning up"

      @watcher.unsubscribe unless @watcher.nil?
      @watcher = nil

      @zk.close! unless @zk.nil?
      @zk = nil

      log.info "synapse: zookeeper watcher cleaned up successfully"
    end

    def zk_connect
      log.info "synapse: zookeeper watcher connecting to ZK at #{@zk_hosts}"
      @zk = ZK.new(@zk_hosts)

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

      return host, port, name
    end
  end
end
