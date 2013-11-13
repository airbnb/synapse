require_relative "./base"

require 'zk'

module Synapse
  class ZookeeperWatcher < BaseWatcher
    def start
      zk_hosts = @discovery['hosts'].shuffle.join(',')

      # support old-style configuration files
      if @discovery['path'].class == String
        log.warn "synapse: zookeeper discovery 'path' section should be a list, not a string"
        @discovery['path'] = [@discovery['path']]
      end

      log.info "synapse: starting ZK watcher #{@name} @ hosts: #{zk_hosts}, paths: #{@discovery['path'].join(',')}"
      @zk = ZK.new(zk_hosts)
      @path_watchers = {}

      # call the callback to bootstrap the process
      watcher_callback.call
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

      new_backends = {}

      @discovery['path'].each do |path|

        begin
          @zk.children(path, :watch => true).map do |name|
            node = @zk.get("#{path}/#{name}")

            begin
              host, port = deserialize_service_instance(node.first)
            rescue
              log.error "synapse: invalid data in ZK node #{name} at #{path}"
            else
              server_port = @server_port_override ? @server_port_override : port

              log.debug "synapse: discovered backend #{name} at #{host}:#{server_port} for service #{@name} at path #{path}"
              (new_backends[path] ||= []) << { 'name' => name, 'host' => host, 'port' => server_port}
            end
          end
        rescue ZK::Exceptions::NoNode
          # the path must exist, otherwise watch callbacks will not work
          create(path)
          retry
        end

      end

      return_backends = []
      @discovery['path'].each do |path|
        if (new_backends[path] ||= []).empty?
          log.warn "synapse: no backends found for service #{@name} at path #{path}"
        else
          log.info "synapse: discovered #{new_backends[path].length} backends for service #{@name} at path #{path}"
          return_backends = new_backends[path]
          # return the first non-empty backend set
          break
        end
      end

      if return_backends.empty?
        if @default_servers.empty?
          log.warn "synapse: no backends at any path and no default servers for service #{@name}; using previous backends: #{@backends.inspect}"
        else
          log.warn "synapse: no backends at any path for service #{@name}; using default servers: #{@default_servers.inspect}"
          @backends = @default_servers
        end
      else
        @backends = return_backends
      end
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      @discovery['path'].each do |path|
        @path_watchers[path].unsubscribe if defined? @watcher
        @path_watchers[path] = @zk.register(path, &watcher_callback)
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
        @synapse.reconfigure!
      end
    end

    # tries to extract host/port from a json hash
    def parse_json(data)
      begin
        json = JSON.parse data
      rescue Object => o
        return false
      end
      raise 'instance json data does not have host key' unless json.has_key?('host')
      raise 'instance json data does not have port key' unless json.has_key?('port')
      return json['host'], json['port']
    end

    # decode the data at a zookeeper endpoint
    def deserialize_service_instance(data)
      log.debug "synapse: deserializing process data"

      # if that does not work, try json
      host, port = parse_json(data)
      return host, port if host

      # if we got this far, then we have a problem
      raise "could not decode this data:\n#{data}"
    end
  end
end
