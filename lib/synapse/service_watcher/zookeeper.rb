require_relative "./base"

require_relative "../../gen-rb/endpoint_types"
require_relative "../../gen-rb/thrift"
require 'zk'

module Synapse
  class ZookeeperWatcher < BaseWatcher
    def start
      log "starting ZK watcher #{@name}, host: #{@discovery['hosts'][0]}, path: #{@discovery['path']}"

      @zk = ZK.new(@discovery['hosts'].shuffle.join(','))
      @deserializer = Thrift::Deserializer.new

      watch
      discover
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
      log "creating path: #{path}"
      # recurse if the parent node does not exist
      create File.dirname(path) unless @zk.exists? File.dirname(path)
      @zk.create(path, ignore: :node_exists)
    end

    # find the current backends at the discovery path; sets @backends
    def discover
      log "discovering services for #{@name}"

      new_backends = []
      begin
        @zk.children(@discovery['path'], :watch => true).map do |name|
          node = @zk.get("#{@discovery['path']}/#{name}")

          begin
            host, port = deserialize_service_instance(node.first)
          rescue
            log "invalid data in node #{name}"
          else
            server_port = @server_port_override ? @server_port_override : port
            log "discovered backend #{name}, #{host}, #{server_port}"
            new_backends << { 'name' => name, 'host' => host, 'port' => server_port}
          end
        end
      rescue ZK::Exceptions::NoNode
        # the path must exist, otherwise watch callbacks will not work
        create(@discovery['path'])
        retry
      else
        STDERR.puts "new_backends is #{new_backends.inspect}"
      end

      @backends = new_backends.empty? ? @default_servers : new_backends
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      @watcher.unsubscribe if defined? @watcher
      @watcher = @zk.register(@discovery['path'], &watcher_callback)
    end

    # handles the event that a watched path has changed in zookeeper
    def watcher_callback
      Proc.new do |event|
        # Set new watcher
        watch
        # Rediscover
        discover
        # send a message to calling class to reconfigure
        @synapse.configure
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

    # tries to extract a host/port from twitter thrift data
    def parse_thrift(data)
      begin
        service = Twitter::Thrift::ServiceInstance.new
        @deserializer.deserialize(service, data)
      rescue Object => o
        return false
      end
      raise "instance thrift data does not have host" if service.serviceEndpoint.host.nil?
      raise "instance thrift data does not have port" if service.serviceEndpoint.port.nil?
      return service.serviceEndpoint.host, service.serviceEndpoint.port
    end

    # decode the data at a zookeeper endpoint
    def deserialize_service_instance(data)
      log "deserializing process data"

      # first, lets try parsing this as thrift
      host, port = parse_thrift(data)
      return host, port if host

      # if that does not work, try json
      host, port = parse_json(data)
      return host, port if host

      # if we got this far, then we have a problem
      raise "could not decode this data:\n#{data}"
    end
  end
end
