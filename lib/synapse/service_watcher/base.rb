require 'synapse/log'
require 'set'

class Synapse::ServiceWatcher
  class BaseWatcher
    include Synapse::Logging

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

      # If there are no default servers and a watcher reports no backends, then
      # use the previous backends that we already know about.
      @use_previous_backends = opts.fetch('use_previous_backends', true)

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
      # Aggregate and deduplicate all potential backend service instances.
      new_backends = (new_backends + @default_servers) if @keep_default_servers
      new_backends = new_backends.uniq {|b|
        [b['host'], b['port'], b.fetch('name', '')]
      }

      if new_backends.to_set == @backends.to_set
        return false
      end

      if new_backends.empty?
        if @default_servers.empty?
          if @use_previous_backends
            # Discard this update
            log.warn "synapse: no backends for service #{@name} and no default" \
              " servers for service #{@name}; using previous backends: #{@backends.inspect}"
            return false
          else
            log.warn "synapse: no backends for service #{@name}, no default" \
              " servers for service #{@name} and 'use_previous_backends' is disabled;" \
              " dropping all backends"
            @backends.clear
          end
        else
          log.warn "synapse: no backends for service #{@name};" \
            " using default servers: #{@default_servers.inspect}"
          @backends = @default_servers
        end
      else
        log.info "synapse: discovered #{new_backends.length} backends for service #{@name}"
        @backends = new_backends
      end

      reconfigure!

      return true
    end

    # Subclasses should not invoke this directly; it's only exposed so that it
    # can be overridden in subclasses.
    def reconfigure!
      @synapse.reconfigure!
    end
  end
end
