require 'synapse/log'

module Synapse
  class BaseWatcher
    include Logging
    attr_reader :name, :backends, :haproxy

    def initialize(opts={}, synapse)
      super()

      @synapse = synapse

      # set required service parameters
      %w{name discovery haproxy}.each do |req|
        raise ArgumentError, "missing required option #{req}" unless opts[req]
      end

      @name = opts['name']
      @discovery = opts['discovery']

      # the haproxy config
      @haproxy = opts['haproxy']
      @haproxy['server_options'] ||= ""
      @haproxy['server_port_override'] ||= nil
      %w{backend frontend listen}.each do |sec|
        @haproxy[sec] ||= []
      end

      unless @haproxy.include?('port')
        log.warn "synapse: service #{name}: haproxy config does not include a port; only backend sections for the service will be created; you must move traffic there manually using configuration in `extra_sections`"
      end

      # set initial backends to default servers, if any
      @default_servers = opts['default_servers'] || []
      @backends = @default_servers

      # set a flag used to tell the watchers to exit
      # this is not used in every watcher
      @should_exit = false

      validate_discovery_opts
    end

    # this should be overridden to actually start your watcher
    def start
      log.info "synapse: starting stub watcher; this means doing nothing at all!"
    end

    # this should be overridden to actually stop your watcher if necessary
    # if you are running a thread, your loop should run `until @should_exit`
    def stop
      log.info "synapse: stopping watcher #{self.name} using default stop handler"
      @should_exit = true
    end

    # this should be overridden to do a health check of the watcher
    def ping?
      true
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method '#{@discovery['method']}' for base watcher" \
        unless @discovery['method'] == 'base'

      log.warn "synapse: warning: a stub watcher with no default servers is pretty useless" if @default_servers.empty?
    end
  end
end
