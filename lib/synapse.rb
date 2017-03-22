require 'logger'
require 'json'

require 'synapse/version'
require 'synapse/log'
require 'synapse/config_generator'
require 'synapse/service_watcher'


module Synapse
  class Synapse

    include Logging

    def initialize(opts={})
      # create objects that need to be notified of service changes
      @config_generators = create_config_generators(opts)
      raise "no config generators supplied" if @config_generators.empty?

      # create the service watchers for all our services
      raise "specify a list of services to connect in the config" unless opts.has_key?('services')
      @service_watchers = create_service_watchers(opts['services'])

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

    def available_generators
      Hash[@config_generators.collect{|cg| [cg.name, cg]}]
    end

    private
    def create_service_watchers(services={})
      service_watchers = []
      services.each do |service_name, service_config|
        service_watchers << ServiceWatcher.create(service_name, service_config, self)
      end

      return service_watchers
    end

    private
    def create_config_generators(opts={})
      config_generators = []
      opts.each do |type, generator_opts|
        # Skip the "services" top level key
        next if (type == 'services' || type == 'service_conf_dir')
        config_generators << ConfigGenerator.create(type, generator_opts)
      end

      return config_generators
    end
  end
end
