require_relative "../gen-rb/endpoint_types"
require_relative "../gen-rb/thrift"

require 'zk'

class ServiceWatcher

  attr_reader :backends, :name, :host, :path, :listen

  def initialize(opts={})
    super()

    raise "you did not specify opts[:name]" if opts[:name].nil?
    raise "you did not specify opts[:listen]" if opts[:listen].nil?
    raise "you did not specify opts[:host]" if opts[:host].nil?
    raise "you did not specify opts[:path]" if opts[:path].nil?
    raise "you did not specify opts[:synapse]" if opts[:synapse].nil?

    @name = opts[:name]
    @listen = opts[:listen]
    @host = opts[:host]
    @path = opts[:path]
    @synapse = opts[:synapse]

    log "starting service #{opts[:name]}, host: #{opts[:host]}, path: #{opts[:path]}"

    @zk = ZK.new(host)
    @deserializer = Thrift::Deserializer.new

    watch
    discover
  end

  private


  def discover
    log "discovering services for #{@name}"
    backends = []
    @service_instances = @zk.children(@path, :watch => true).map do |name|
      node = @zk.get("#{@path}/#{name}")
      host, port = deserialize_service_instance(node.first)
      log "discovered backend #{name}, #{host}, #{port}"
      backends << {name: name, host: host, port: port}
    end
    @backends = backends
  end


  def watch
    @watcher.unsubscribe if defined? @watcher
    @watcher = @zk.register(@service_path, &watcher_callback)
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


  def deserialize_service_instance(data)
    log "deserializing process data"

    # first, lets try parsing this as thrift
    host, port = parse_thrift(data)
    return host, port if host

    # if that does not work, try json
    host, port = parse_json(data)
    return host, port if host

    # if we got this far, then we have a problem
    raise "could not decode this data: #{data}"
  end

end
