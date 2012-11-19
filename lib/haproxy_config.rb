class HaproxyConfig < Mustache
  self.path = File.dirname(__FILE__)

  def initialize
    super()
    @services = {}
  end

  def set_nodes(name, nodes)
    @services[name] = nodes
  end

  def services
    @services.map do |name, nodes|
      {name: name, nodes: nodes}
    end
  end

end
