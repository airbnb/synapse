require_relative "synapse/version"
require_relative "synapse/base"
require_relative "synapse/haproxy"
require_relative "synapse/zookeeper"

require 'logger'
require 'json'


# at_exit do
#   @@log "exiting synapse"
# end

module Synapse
  
  attr_reader :service_watchers

  class Synapse < Base
    def initialize(opts={})
      raise "you need to pass opts[:services]" if opts[:services].nil?
      @service_watchers = start_service_watchers(opts[:services])
      @haproxy_opts = {}
      @haproxy = Haproxy.new(@haproxy_opts)

      configure
    end


    def configure()
      config = generate_haproxy_config
      log "haproxy config is:\n#{config}"
    end

    private

    def generate_haproxy_config()
      haproxy_config = @haproxy.generate_base_config

      @service_watchers.each do |service_watcher|
        backend_opts = {name: service_watcher.name, listen: service_watcher.listen}
        haproxy_config << @haproxy.generate_service_config(backend_opts,service_watcher.backends)
      end

      log "haproxy_config is :"
      log "\n#{haproxy_config}"
      return haproxy_config
    end

    
    def start_service_watchers(services={})
      service_watcher_array =[]
      services.each do |name,params|
        service_watcher_array << ServiceWatcher.new({name: name, host: params[:host], path: params[:path], listen: params[:listen], synapse: self})
      end
      return service_watcher_array
    end
    
  end
end
