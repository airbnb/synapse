require 'zk'
class ServiceWatcher

  attr_reader :backends, :name, :host, :path, :listen

  def initialize(opts={})
#  def initialize(service_path, zookeeper_host = 'localhost:2181', &block)
    super()

    raise "you did not specify opts[:name]" if opts[:name].nil?
    raise "you did not specify opts[:listen]" if opts[:listen].nil?
    raise "you did not specify opts[:host]" if opts[:host].nil?
    raise "you did not specify opts[:path]" if opts[:path].nil?
    
    @name = opts[:name]
    @listen = opts[:listen]
    @host = opts[:host]
    @path = opts[:path]

    log "starting service #{opts[:name]}, host: #{opts[:host]}, path: #{opts[:path]}"
    
    @zk = ZK.new(host)
    @deserializer = Thrift::Deserializer.new

#    watch
    discover
  end

  def discover
    log "discovering services for #{@name}"
    backends = []
    @service_instances = @zk.children(@path, :watch => true).map do |name|
      node = @zk.get("#{@path}/#{name}")
      host, port = deserialize_service_instance(node.first)
      log "discovered backend #{name}, #{host}, #{port}"
      backends << {name: name, host: host, port: port}
    end

#    @block.call(@service_instances)
    @backends = backends
  end

  def watch
    @watcher.unsubscribe if defined? @watcher
    @watcher = @zk.register(@service_path, &watcher_callback)
  end

  private

  def watcher_callback
    Proc.new do |event|
      # Set new watcher
      watch
      # Rediscover
      discover
    end
  end

  def deserialize_service_instance(data)
    log "deserializing process"
    service = Twitter::Thrift::ServiceInstance.new
    begin 
      @deserializer.deserialize(service, data)
    rescue Object => o
      STDERR.puts "o is #{o.inspect}"
    end
    log "deserialized some data for #{service.inspect}"
    return service.serviceEndpoint.host, service.serviceEndpoint.port
  end

end
