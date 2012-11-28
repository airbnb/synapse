require_relative "synapse/version"
require_relative "synapse/base"
require_relative "synapse/haproxy"
require_relative "synapse/thrift"
require_relative "gen-rb/endpoint_types"
require_relative "synapse/zookeeper"

require 'logger'


# at_exit do
#   @@log "exiting synapse"
# end

module Synapse
  
  attr_reader :service_watchers

  class Synapse < Base
    def initialize(opts={})
#      @@log = Logger.new(STDERR)

      raise "you need to pass opts[:services]" if opts[:services].nil?
      @service_watchers = start_service_watchers(opts[:services])

      haproxy_opts = {}
      @haproxy = Haproxy.new(haproxy_opts)

      haproxy_config = @haproxy.generate_main_config

      @service_watchers.each do |service_watcher|
        # log "service_watcher #{service_watcher.name} has these backends:"
        # log "  #{service_watcher.backends.inspect}"

        backend_opts = {name: service_watcher.name, listen: service_watcher.listen}
        haproxy_config << @haproxy.generate_service_config(backend_opts,service_watcher.backends)
        # log "service_watcher #{service_watcher.name} has this haproxy section:"
        # log "\n#{@haproxy.generate_service_config(backend_opts,service_watcher.backends)}"
      end

      log "haproxy_config is :"
      log "\n#{haproxy_config}"

      log "exiting for testing"
      Kernel.exit 1

      foo(opts)
    end

    private
    
    def start_service_watchers(services={})
      a=[]
      services.each do |name,params|
        a << ServiceWatcher.new({name: name, host: params[:host], path: params[:path], listen: params[:listen]})
      end
      a
    end
    
    def foo(opts)
      sw = ServiceWatcher.new(opts[:path],opts[:host])
    end
  end
end
