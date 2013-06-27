require_relative "synapse/version"
require_relative "synapse/base"
require_relative "synapse/haproxy"
require_relative "synapse/service_watcher"

require 'logger'
require 'json'

include Synapse

module Synapse
  class Synapse
    def initialize(opts={})
      # create the service watchers for all our services
      raise "specify a list of services to connect in the config" unless opts.has_key?('services')
      @service_watchers = create_service_watchers(opts['services'])

      # create the haproxy object
      raise "haproxy config section is missing" unless opts.has_key?('haproxy')
      @haproxy = Haproxy.new(opts['haproxy'])

      # configuration is initially enabled to configure on first loop
      @config_updated = true
    end

    # start all the watchers and enable haproxy configuration
    def run
      log.info "synapse: starting..."

      # start all the watchers
      @service_watchers.map { |watcher| watcher.start }

      # main loop
      loops = 0
      loop do
        @service_watchers.each do |w|
          raise "synapse: service watcher #{w.name} failed ping!" unless w.ping?
        end

        if @config_updated
          @config_updated = false
          log.info "synapse: regenerating haproxy config"
          @haproxy.update_config(@service_watchers)
        else
          sleep 1
        end

        loops += 1
        log.debug "synapse: still running at #{Time.now}" if (loops % 60) == 0
      end
    end

    def reconfigure!
      @config_updated = true
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
