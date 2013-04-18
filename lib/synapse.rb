require_relative "synapse/version"
require_relative "synapse/base"
require_relative "synapse/haproxy"
require_relative "synapse/service_watcher"

require 'logger'
require 'json'

include Synapse

module Synapse
  
  attr_reader :service_watchers

  class Synapse < Base
    def initialize(opts={})
      # disable configuration until this is started
      @configure_enabled = false

      # create the service watchers for all our services
      raise "specify a list of services to connect in the config" unless opts.has_key?('services')
      @service_watchers = create_service_watchers(opts['services'])

      # create the haproxy object
      raise "haproxy config section is missing" unless opts.has_key?('haproxy')
      @haproxy = Haproxy.new(opts['haproxy'])
    end

    # start all the watchers and enable haproxy configuration
    def run
      log.info "synapse: starting..."

      @service_watchers.map { |watcher| watcher.start }
      @configure_enabled = true
      configure

      # loop forever
      loops = 0
      loop do 
        sleep 1
        loops += 1
        log.debug "synapse: still running at #{Time.now}" if (loops % 60) == 0
      end
    end

    # reconfigure haproxy based on our watchers
    def configure
      if @configure_enabled
        log.info "synapse: regenerating haproxy config"
        @haproxy.update_config(@service_watchers)
      else
        log.info "synapse: reconfigure requested, but it's not yet enabled"
      end
    end

    private
    def create_service_watchers(services={})
      service_watchers =[]
      services.each do |service_config|
        service_watchers << ServiceWatcher.create(service_config, self)
      end
      
      return service_watchers
    end
    
  end
end
