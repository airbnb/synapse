require "synapse/service_watcher/base"

require 'etcd'

module Synapse
  class EtcdWatcher < BaseWatcher
    NUMBERS_RE = /^\d+$/

    def start
      etcd_hosts = @discovery['host']

      log.info "synapse: starting etcd watcher #{@name} @ host: #{@discovery['host']}, path: #{@discovery['path']}"
      @should_exit = false
      @etcd = ::Etcd.client(:host => @discovery['host'], :port => @discovery['port'])

      # call the callback to bootstrap the process
      discover
      @synapse.reconfigure!
      @watcher = Thread.new do
        watch
      end
    end

    def stop
      log.warn "synapse: etcd watcher exiting"

      @should_exit = true
      @etcd = nil

      log.info "synapse: etcd watcher cleaned up successfully"
    end

    def ping?
      @etcd.leader
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'etcd'
      raise ArgumentError, "missing or invalid etcd host for service #{@name}" \
        unless @discovery['host']
      raise ArgumentError, "missing or invalid etcd port for service #{@name}" \
        unless @discovery['port']
      raise ArgumentError, "invalid etcd path for service #{@name}" \
        unless @discovery['path']
    end

    # helper method that ensures that the discovery path exists
    def create(path)
      log.debug "synapse: creating etcd path: #{path}"
      @etcd.create(path, dir: true)
    end

    def each_node(node)
      begin
        host, port, name = deserialize_service_instance(node.value)
      rescue StandardError => e
        log.error "synapse: invalid data in etcd node #{node.inspect} at #{@discovery['path']}: #{e} DATA #{node.value}"
        nil 
     else
        server_port = @server_port_override ? @server_port_override : port

        # find the numberic id in the node name; used for leader elections if enabled
        numeric_id = node.key.split('/').last
        numeric_id = NUMBERS_RE =~ numeric_id ? numeric_id.to_i : nil

        log.warn "synapse: discovered backend #{name} at #{host}:#{server_port} for service #{@name}"
        { 'name' => name, 'host' => host, 'port' => server_port, 'id' => numeric_id}
      end
    end

    def each_dir(d)
      new_backends = []
      d.children.each do |node|
        if node.directory?
          new_backends << each_dir(@etcd.get(node.key))
        else
          backend = each_node(node)
          if backend
            new_backends << backend
          end
        end
      end
      new_backends.flatten
    end

    # find the current backends at the discovery path; sets @backends
    def discover
      log.info "synapse: discovering backends for service #{@name}"

      d = nil
      begin
        d = @etcd.get(@discovery['path'])
      rescue Etcd::KeyNotFound
        create(@discovery['path'])
        d = @etcd.get(@discovery['path'])
      end

      new_backends = []
      if d.directory?
        new_backends = each_dir(d)
      else
        log.warn "synapse: path #{@discovery['path']} is not a directory"
      end

      if new_backends.empty?
        if @default_servers.empty?
          log.warn "synapse: no backends and no default servers for service #{@name}; using previous backends: #{@backends.inspect}"
          false
        else
          log.warn "synapse: no backends for service #{@name}; using default servers: #{@default_servers.inspect}"
          @backends = @default_servers
          true
        end
      else
        if @backends != new_backends
          log.info "synapse: discovered #{new_backends.length} backends (including new) for service #{@name}"
          @backends = new_backends
          true
        else
          log.info "synapse: discovered #{new_backends.length} backends for service #{@name}"
          false
        end
      end
    end

    def watch
      while !@should_exit
        begin
          @etcd.watch(@discovery['path'], :timeout => 60, :recursive => true)
        rescue Timeout::Error
        else
          if discover
            @synapse.reconfigure!
          end
        end
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

