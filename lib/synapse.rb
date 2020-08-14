require 'logger'
require 'json'
require 'uri'
require 'aws-sdk'

require 'synapse/version'
require 'synapse/log'
require 'synapse/statsd'
require 'synapse/config_generator'
require 'synapse/service_watcher'
require 'synapse/atomic'
require 'synapse/version'

module Synapse
  class Synapse

    include Logging
    include StatsD

    def initialize(opts={})
      StatsD.configure_statsd(opts["statsd"] || {})

      # configure AWS clients to use custom endpoint
      if ENV.has_key?('AWS_ENDPOINT_URL')
        aws_endpoint = URI(ENV['AWS_ENDPOINT_URL'])
        AWS.config(s3_endpoint: aws_endpoint.host,
                   s3_port: aws_endpoint.port,
                   s3_force_path_style: true,
                   use_ssl: aws_endpoint.scheme == 'https')
      end

      # create objects that need to be notified of service changes
      @config_generators = create_config_generators(opts)
      raise "no config generators supplied" if @config_generators.empty?

      # create the service watchers for all our services
      raise "specify a list of services to connect in the config" unless opts.has_key?('services')
      @service_watchers = create_service_watchers(opts['services'])

      # configuration is initially enabled to configure on first loop
      @config_updated = AtomicValue.new(true)

      # TODO(rushy_panchal): minimum and maximum thread counts
      @task_scheduler = Concurrent.TimerSet.new(:executor => Concurrent::ThreadPoolExecutor.new)

      # Any exceptions in the watcher threads should wake the main thread so
      # that we can fail fast.
      Thread.abort_on_exception = true

      log.debug "synapse: completed init"
    rescue Exception => e
      statsd && statsd_increment('synapse.stop', ['stop_avenue:abort', 'stop_location:init', "exception_name:#{e.class.name}", "exception_message:#{e.message}"])
      raise e
    end

    # start all the watchers and enable haproxy configuration
    def run
      log.info "synapse: starting..."
      statsd_increment('synapse.start')

      # start all the watchers
      statsd_time('synapse.watchers.start.time') do
        @service_watchers.map do |watcher|
          begin
            watcher.start(@task_scheduler)
            statsd_increment("synapse.watcher.start", ['start_result:success', "watcher_name:#{watcher.name}"])
          rescue Exception => e
            statsd_increment("synapse.watcher.start", ['start_result:fail', "watcher_name:#{watcher.name}", "exception_name:#{e.class.name}", "exception_message:#{e.message}"])
            raise e
          end
        end
      end

      statsd_time('synapse.main_loop.elapsed_time') do
        # main loop
        loops = 0
        loop do
          @service_watchers.each do |w|
            alive = w.ping?
            statsd_increment('synapse.watcher.ping.count', ["watcher_name:#{w.name}", "ping_result:#{alive ? "success" : "failure"}", "synapse_version:#{VERSION}"])
            raise "synapse: service watcher #{w.name} failed ping!" unless alive
          end

          if @config_updated.get_and_set(false)
            statsd_increment('synapse.config.update')
            @config_generators.each do |config_generator|
              log.info "synapse: configuring #{config_generator.name}"
              begin
                config_generator.update_config(@service_watchers)
              rescue StandardError => e
                statsd_increment("synapse.config.update_failed", ["config_name:#{config_generator.name}"])
                log.error "synapse: update config failed for config #{config_generator.name} with exception #{e}"
                raise e
              end
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
      statsd_increment('synapse.stop', ['stop_avenue:abort', 'stop_location:main_loop', "exception_name:#{e.class.name}", "exception_message:#{e.message}"])
      log.error "synapse: encountered unexpected exception #{e.inspect} in main thread"
      raise e
    ensure
      log.warn "synapse: exiting; sending stop signal to all watchers"

      # stop all the watchers
      @service_watchers.map do |w|
        begin
          w.stop
          statsd_increment("synapse.watcher.stop", ['stop_avenue:clean', 'stop_location:main_loop', "watcher_name:#{w.name}"])
        rescue Exception => e
          statsd_increment("synapse.watcher.stop", ['stop_avenue:exception', 'stop_location:main_loop', "watcher_name:#{w.name}", "exception_name:#{e.class.name}", "exception_message:#{e.message}"])
          raise e
        end
      end

      @task_scheduler.kill
      statsd_increment('synapse.stop', ['stop_avenue:clean', 'stop_location:main_loop'])
    end

    def reconfigure!
      @config_updated.set(true)
    end

    def available_generators
      Hash[@config_generators.collect{|cg| [cg.name, cg]}]
    end

    private
    def create_service_watchers(services={})
      service_watchers = []
      reconfigure_callback = ->(*args) { reconfigure! }

      services.each do |service_name, service_config|
        if service_config.has_key?('load_test_concurrency')
          concurrency = service_config['load_test_concurrency']
          concurrency.times do |i|
            service_watchers << ServiceWatcher.create("#{service_name}_#{i}", service_config, self, reconfigure_callback)
          end
        else
          service_watchers << ServiceWatcher.create(service_name, service_config, self, reconfigure_callback)
        end
      end

      return service_watchers
    end

    private

    WAIVED_CONFIG_SECTIONS = [
      'services',
      'service_conf_dir',
      'statsd',
    ].freeze

    def create_config_generators(opts={})
      config_generators = []
      opts.each do |type, generator_opts|
        # Skip the "services" top level key
        next if WAIVED_CONFIG_SECTIONS.include? type
        config_generators << ConfigGenerator.create(type, generator_opts)
      end

      return config_generators
    end
  end
end
