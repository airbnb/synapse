require "synapse/version"
require "synapse/service_watcher/base"
require "synapse/haproxy"
require "synapse/service_watcher"
require "synapse/log"

require 'logger'
require 'json'

include Synapse

module Synapse
  class Synapse
    include Logging
    def initialize(opts={})
      # create the service watchers for all our services
      raise "specify a list of services to connect in the config" unless opts.has_key?('services')
      @service_watchers = create_service_watchers(opts['services'])

      # create the haproxy object
      raise "haproxy config section is missing" unless opts.has_key?('haproxy')
      @haproxy = Haproxy.new(opts['haproxy'])

      # configuration is initially enabled to configure on first loop
      @config_updated = true

      # Any exceptions in the watcher threads should wake the main thread so
      # that we can fail fast.
      Thread.abort_on_exception = true
      if opts['check_interval']
        @check_interval = opts['check_interval'].to_i
      else
        @check_interval = 15
      end 
      if opts['max_checks']
        @max_checks = opts['max_checks'].to_i
      else
        @max_checks = 0
      end 

      log.debug "synapse: completed init"
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
          sleep @check_interval
        end

        loops += 1
        if @max_checks != 0 and loops > @max_checks
            log.info "synapse: exiting after #{loops} loops"
            break
        end
        log.debug "synapse: still running at #{Time.now}" if (loops % 60) == 0
      end

    rescue StandardError => e
      log.error "synapse: encountered unexpected exception #{e.inspect} in main thread"
      raise e
    ensure
      log.warn "synapse: exiting; sending stop signal to all watchers"

      # stop all the watchers
      @service_watchers.map(&:stop)
    end

    def reconfigure!
      @config_updated = true
    end

    private
    def create_service_watchers(services={})
      service_watchers =[]
      services.each do |service_name, service_config|
        service_watchers << ServiceWatcher.create(service_name, service_config, self)
      end

      return service_watchers
    end

  end
end
