require "synapse/version"
require "synapse/service_watcher/base"
require "synapse/haproxy"
require "synapse/file_output"
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

      # create objects that need to be notified of service changes
      @config_generators = []
      # create the haproxy config generator, this is mandatory
      raise "haproxy config section is missing" unless opts.has_key?('haproxy')
      @config_generators << Haproxy.new(opts['haproxy'])

      # possibly create a file manifestation for services that do not
      # want to communicate via haproxy, e.g. cassandra
      if opts.has_key?('file_output')
        @config_generators << FileOutput.new(opts['file_output'])
      end

      # configuration is initially enabled to configure on first loop
      @config_updated = true

      # Any exceptions in the watcher threads should wake the main thread so
      # that we can fail fast.
      Thread.abort_on_exception = true

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
          @config_generators.each do |config_generator|
            log.info "synapse: configuring #{config_generator.name}"
            config_generator.update_config(@service_watchers)
          end
        end

        sleep 1
        @config_generators.each do |config_generator|
          config_generator.tick(@service_watchers)
        end

        loops += 1
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
