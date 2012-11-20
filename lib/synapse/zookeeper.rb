class ServiceWatcher

  def initialize(service_path, zookeeper_host = 'localhost:2181', &block)
    @service_path = service_path
    @zk = ZK.new(zookeeper_host)
    @block = block
    @deserializer = Thrift::Deserializer.new

    watch
    discover
  end

  def discover
    @service_instances = @zk.children(@service_path, :watch => true).map do |node_name|
      node = @zk.get("#{@service_path}/#{node_name}")
      deserialize_service_instance(node.first)
    end

    @block.call(@service_instances)
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
    service = Twitter::Thrift::ServiceInstance.new
    @deserializer.deserialize(service, data)
    service
  end

end
