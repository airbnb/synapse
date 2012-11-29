require_relative "synapse/version"
require_relative "synapse/base"
require_relative "synapse/haproxy"
require_relative "synapse/zookeeper"

require 'logger'
require 'json'

include Synapse

# at_exit do
#   @@log "exiting synapse"
# end

module Synapse
  
  attr_reader :service_watchers

  class Synapse < Base
    def initialize(opts={})
      # create watchers for each service
      raise "you need to pass opts[:services]" unless opts.has_key?('services')
      @services = opts['services']

      # create the haproxy object
      @haproxy = Haproxy.new(opts['haproxy'])
    end

    def run
      log "starting synapse..."

      @service_watchers = start_service_watchers(@services)
      configure

      # loop forever
      loops = 0
      loop do 
        sleep 1
        loops += 1
        log Time.now if (loops % 60) == 0
      end
    end

    def configure
      # some watcher changed backends; regenerate haproxy config and restart
      log "regenerating haproxy config"
      @haproxy.update_config(@service_watchers)
    end

    private
    
    def start_service_watchers(services={})
      service_watchers =[]
      services.each do |service_config|
        service_watchers << ServiceWatcher.new(service_config, self)
      end
      
      return service_watchers
    end
    
  end
end
