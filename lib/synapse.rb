require_relative "synapse/version"
require_relative "synapse/base"
require_relative "synapse/haproxy"
require_relative "synapse/service_watcher"
require_relative "synapse/service_discoverer"

require 'logger'
require 'json'

include Synapse

module Synapse
  class Synapse
    def initialize(opts={})

      # create the service watchers for all our static services
      raise "specify a list of services to connect in the config" unless opts.has_key?('services')
      @static_service_watchers = create_static_service_watchers(opts['services'])
      @dynamic_service_watchers = []

      # Do we have a dynamic list?
      if opts.key?('service_discoverer')
        # Load up the service discoveror
        @service_discoverer = create_service_discoverer(opts['service_discoverer'])
      else
        # Static
        @service_discoverer = nil
      end

      # create the haproxy object
      raise "haproxy config section is missing" unless opts.has_key?('haproxy')
      @haproxy = Haproxy.new(opts['haproxy'])

      # configuration is initially enabled to configure on first loop
      @config_updated = true
    end

    # start all the watchers and enable haproxy configuration
    def run
      log.info "synapse: starting..."

      # Start the service discoverer
      @service_discoverer.start

      # start all the static watchers
      @static_service_watchers.map { |watcher| watcher.start }

      # main loop
      loops = 0
      loop do

        update_service_watchers

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
    def create_static_service_watchers(services={})
      service_watchers =[]
      services.each do |service_name, service_config|
        service_watchers << ServiceWatcher.create(service_name, service_config, self)
      end

      return service_watchers
    end

    private
    def create_service_discoverer(opts)
      static_service_names = @static_service_watchers.map { |watcher| watcher.name }
      return ServiceDiscoverer.create(opts, static_service_names, self)
    end

    private
    def update_service_watchers

      # If we don't have a service discoverer then we just want to return the static service
      # watchers
      unless @service_discoverer
        @service_watchers = @static_service_watchers
      else
        # We have a service discoverer - is it available?
        raise "synapse: service discoverer failed ping!" unless @service_discoverer.ping?

        # We need to modify our list of dynamic service watchers. First remove any that
        # aren't present in the discoverer's service list
        discovered = @service_discoverer.services
        @dynamic_service_watchers.keep_if { |svc| discovered.key?(svc.name) }

        # Create any new watchers and add them to the list
        discovered.each do |service_name, config|
          if @dynamic_service_watchers.index { |svc| svc.name == service_name }.nil?
            # Isn't in the list - lets add it and start it
            watcher = ServiceWatcher.create(service_name, config, self)
            watcher.start
            @dynamic_service_watchers << watcher
          end
        end

        # Now merge the two arrays
        @service_watchers = @static_service_watchers | @dynamic_service_watchers

      end
    end
  end
end
