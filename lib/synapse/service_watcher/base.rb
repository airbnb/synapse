require 'synapse/log'
require 'set'

class Synapse::ServiceWatcher
  class BaseWatcher
    include Synapse::Logging

    LEADER_WARN_INTERVAL = 30

    attr_reader :name, :config_for_generator, :revision

    def initialize(opts={}, synapse)
      super()

      @synapse = synapse
      @revision = 0

      # set required service parameters
      %w{name discovery}.each do |req|
        raise ArgumentError, "missing required option #{req}" unless opts[req]
      end

      @name = opts['name']
      @discovery = opts['discovery']

      # deprecated singular filter
      @singular_label_filter = @discovery['label_filter']
      unless @singular_label_filter.nil?
        log.warn "synapse: `label_filter` parameter is deprecated; use `label_filters` -- an array"
      end

      @label_filters = [@singular_label_filter, @discovery['label_filters']].flatten.compact

      @leader_election = opts['leader_election'] || false
      @leader_last_warn = Time.now - LEADER_WARN_INTERVAL

      @config_for_generator = Hash[
        @synapse.available_generators.collect do |generator_name, generator|
          watcher_provided_config = opts[generator_name] || {}
          normalized_generator_opts = generator.normalize_watcher_provided_config(
            @name, watcher_provided_config
          )
          [generator_name, normalized_generator_opts]
        end
      ]

      # set initial backends to default servers, if any
      @default_servers = opts['default_servers'] || []
      @backends = @default_servers

      @keep_default_servers = opts['keep_default_servers'] || false

      # If there are no default servers and a watcher reports no backends, then
      # use the previous backends that we already know about.
      @use_previous_backends = opts.fetch('use_previous_backends', true)

      # If backends discovered with this watcher lack ports or discovered
      # ports should be ignored, this option indicates that
      @backend_port_override = opts['backend_port_override'] || nil

      # For backwards compatability we support server_port_override
      # This will be removed in future versions
      if @backend_port_override.nil? && @config_for_generator['haproxy']
        @backend_port_override = @config_for_generator['haproxy']['server_port_override']
      end

      unless @backend_port_override.nil?
        unless @backend_port_override.to_s.match(/^\d+$/)
          raise ArgumentError, "Invalid backend_port_override value"
        end
      end

      # set a flag used to tell the watchers to exit
      # this is not used in every watcher
      @should_exit = false

      validate_discovery_opts
    end

    def haproxy
      log.warn "synapse: service watcher #{@name} accessing watcher.haproxy. This is DEPRECATED and will be removed in future iterations, use watcher.config_for_generator['haproxy'] instead."
      config_for_generator['haproxy']
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
      filtered = backends_filtered_by_labels

      if @leader_election
        failure_warning = nil
        if filtered.empty?
          failure_warning = "synapse: service #{@name}: leader election failed: no backends to choose from"
        end

        all_backends_have_ids = filtered.all?{|b| b.key?('id') && b['id']}
        unless all_backends_have_ids
          failure_warning = "synapse: service #{@name}: leader election failed; not all backends include an id"
        end

        # no problems encountered, lets do the leader election
        if failure_warning.nil?
          smallest = filtered.sort_by{ |b| b['id']}.first
          log.debug "synapse: leader election chose one of #{filtered.count} backends " \
            "(#{smallest['host']}:#{smallest['port']} with id #{smallest['id']})"

          return [smallest]

        # we had some sort of problem, lets log about it
        elsif (Time.now - @leader_last_warn) > LEADER_WARN_INTERVAL
          @leader_last_warn = Time.now
          log.warn failure_warning
          return []
        end
      end

      return filtered
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method '#{@discovery['method']}' for base watcher" \
        unless @discovery['method'] == 'base'

      log.warn "synapse: warning: a stub watcher with no default servers is pretty useless" if @default_servers.empty?
    end

    def backends_filtered_by_labels
      filtered_backends = @backends.select do |backend|
        backend_labels = backend['labels'] || {}
        @label_filters.all? do |label_filter|
          (label_filter['condition'] == 'equals' &&
            backend_labels[label_filter['label']] == label_filter['value']) ||
          (label_filter['condition'] == 'not-equals' &&
            backend_labels[label_filter['label']] != label_filter['value'])
        end
      end
    end

    def set_backends(new_backends)
      # Aggregate and deduplicate all potential backend service instances.
      new_backends = (new_backends + @default_servers) if @keep_default_servers
      # Substitute backend_port_override for the provided port
      new_backends = new_backends.collect do |b|
        port = @backend_port_override ? @backend_port_override : b['port']
        b.merge({'port' => port})
      end

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
      @revision += 1
      @synapse.reconfigure!
    end
  end
end
