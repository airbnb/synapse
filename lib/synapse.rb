require 'logger'
require 'json'

require 'synapse/version'
require 'synapse/log'
require 'synapse/statsd'
require 'synapse/config_generator'
require 'synapse/service_watcher'


module Synapse
  class Synapse

    include Logging
    include StatsD

    def initialize(opts={})
      StatsD.configure_statsd(opts["statsd"] || {})

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
    rescue Exception => e
      statsd && statsd.increment('synapse.stop', tags: ['stop_avenue:abort', 'stop_location:init'])
      raise e
    end

    # start all the watchers and enable haproxy configuration
    def run
      log.info "synapse: starting..."
      statsd.increment('synapse.start')

      # start all the watchers
      statsd.time('synapse.watchers.start.time') do
        @service_watchers.map do |watcher|
          begin
            watcher.start
            statsd.increment("synapse.watcher.start", tags: ['start_result:success', "watcher_name:#{watcher.name}"])
          rescue Exception => e
            statsd.increment("synapse.watcher.start", tags: ['start_result:fail', "watcher_name:#{watcher.name}"])
            raise e
          end
        end
      end

      statsd.time('synapse.main_loop.elapsed_time') do
        # main loop
        loops = 0
        loop do
          @service_watchers.each do |w|
            alive = w.ping?
            statsd.increment('synapse.watcher.ping.count', tags: ["watcher_name:#{w.name}", "ping_result:#{alive ? "success" : "failure"}"])
            raise "synapse: service watcher #{w.name} failed ping!" unless alive
          end

          if @config_updated
            @config_updated = false
            statsd.increment('synapse.config.update')
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
      end

    rescue StandardError => e
      statsd.increment('synapse.stop', tags: ['stop_avenue:abort', 'stop_location:main_loop'])
      log.error "synapse: encountered unexpected exception #{e.inspect} in main thread"
      raise e
    ensure
      log.warn "synapse: exiting; sending stop signal to all watchers"

      # stop all the watchers
      @service_watchers.map do |w|
        begin
          w.stop
          statsd.increment("synapse.watcher.stop", tags: ['stop_avenue:clean', 'stop_location:main_loop', "watcher_name:#{w.name}"])
        rescue Exception => e
          statsd.increment("synapse.watcher.stop", tags: ['stop_avenue:exception', 'stop_location:main_loop', "watcher_name:#{w.name}"])
          raise e
        end
      end
      statsd.increment('synapse.stop', tags: ['stop_avenue:clean', 'stop_location:main_loop'])
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
