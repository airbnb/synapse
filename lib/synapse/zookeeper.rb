require_relative "../gen-rb/endpoint_types"
require_relative "../gen-rb/thrift"

require 'zk'

module Synapse
  class ServiceWatcher

    attr_reader :backends, :name, :listen, :local_port, :server_options

    def initialize(opts={}, synapse)
      super()
      @backends = opts['default_servers']
      @synapse = synapse

      %w{name discovery local_port}.each do |req|
        raise ArgumentError, "missing required option #{req}" unless opts[req]
      end

      @name = opts['name']
      @listen = opts['listen']
      @local_port = opts['local_port']
      @server_options = opts['server_options']

      @discovery = opts['discovery']
      raise ArgumentError, "invalid discovery type #{@discovery['type']}" unless @discovery['type'] == 'zookeeper' 
      raise ArgumentError, "missing or invalid zookeeper host for service #{@name}" unless @discovery['hosts']
      raise ArgumentError, "invalid zookeeper path for service #{@name}" unless @discovery['path']

      log "starting service watcher #{@name}, host: #{@discovery['hosts'][0]}, path: #{@discovery['path']}"
      @zk = ZK.new(@discovery['hosts'][0])
      @deserializer = Thrift::Deserializer.new

      watch
      discover
    end

    private
    # find the current backends at the discovery path; sets @backends
    def discover
      log "discovering services for #{@name}"

      new_backends = []
      @zk.children(@discovery['path'], :watch => true).map do |name|
        node = @zk.get("#{@path}/#{name}")

        begin
          host, port = deserialize_service_instance(node.first)
        rescue
          log "invalid data in node #{name}"
        else
          log "discovered backend #{name}, #{host}, #{port}"
          new_backends << { :name => name, :host => host, :port => port}
        end
      end
      @backends = new_backends unless new_backends.empty?
    end


    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      @watcher.unsubscribe if defined? @watcher
      @watcher = @zk.register(@discovery['path'], &watcher_callback)
    end

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
