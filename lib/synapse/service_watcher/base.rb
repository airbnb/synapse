require 'synapse/log'

module Synapse
  class BaseWatcher
    include Logging

    LEADER_WARN_INTERVAL = 30

    attr_reader :name, :haproxy

    def initialize(opts={}, synapse)
      super()

      @synapse = synapse

      # set required service parameters
      %w{name discovery haproxy}.each do |req|
        raise ArgumentError, "missing required option #{req}" unless opts[req]
      end

      @name = opts['name']
      @discovery = opts['discovery']

      @leader_election = opts['leader_election'] || false
      @leader_last_warn = Time.now - LEADER_WARN_INTERVAL

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

      @keep_default_servers = opts['keep_default_servers'] || false

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

    def backends
      if @leader_election
        if @backends.all?{|b| b.key?('id') && b['id']}
          smallest = @backends.sort_by{ |b| b['id']}.first
          log.debug "synapse: leader election chose one of #{@backends.count} backends " \
            "(#{smallest['host']}:#{smallest['port']} with id #{smallest['id']})"

          return [smallest]
        elsif (Time.now - @leader_last_warn) > LEADER_WARN_INTERVAL
          log.warn "synapse: service #{@name}: leader election failed; not all backends include an id"
          @leader_last_warn = Time.now
        end

        # if leader election fails, return no backends
        return []
      end

      return @backends
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method '#{@discovery['method']}' for base watcher" \
        unless @discovery['method'] == 'base'

      log.warn "synapse: warning: a stub watcher with no default servers is pretty useless" if @default_servers.empty?
    end

    def set_backends(new_backends)
      if @keep_default_servers
        @backends = @default_servers + new_backends
      else
        @backends = new_backends
      end
    end

    def reconfigure!
      @synapse.reconfigure!
    end
  end
end
