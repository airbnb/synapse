require 'synapse/config_generator/base'

require 'csv'
require 'fileutils'
require 'json'
require 'socket'
require 'digest/sha1'
require 'set'

class Synapse::ConfigGenerator
  class Haproxy18 < BaseGenerator
    include Synapse::Logging

    NAME = 'haproxy18'.freeze

    HAPROXY_CMD_BATCH_SIZE = 4

    DEFAULT_STATE_FILE_TTL = (60 * 60 * 24).freeze # 24 hours
    STATE_FILE_UPDATE_INTERVAL = 60.freeze # iterations; not a unit of time
    DEFAULT_BIND_ADDRESS = 'localhost'

    def initialize(opts)
      super(opts)

      %w{global defaults}.each do |req|
        raise ArgumentError, "haproxy requires a #{req} section" if !opts.has_key?(req)
      end

      @opts['do_writes'] = true unless @opts.key?('do_writes')
      @opts['do_socket'] = true unless @opts.key?('do_socket')
      @opts['do_reloads'] = true unless @opts.key?('do_reloads')

      req_pairs = {
        'do_writes' => 'config_file_path',
        'do_socket' => 'socket_file_path',
        'do_reloads' => 'reload_command'
      }

      req_pairs.each do |cond, req|
        if @opts[cond]
          raise ArgumentError, "the `#{req}` option is required when `#{cond}` is true" unless @opts[req]
        end
      end

      # socket_file_path can be a string or a list
      # lets make a new option which is always a list (plural)
      @opts['socket_file_paths'] = [@opts['socket_file_path']].flatten

      # how to restart haproxy
      @restart_interval = @opts.fetch('restart_interval', 2).to_i
      @restart_jitter = @opts.fetch('restart_jitter', 0).to_f
      @restart_required = true

      # virtual clock bookkeeping for controlling how often haproxy restarts
      @time = 0
      @next_restart = @time

      # a place to store the parsed haproxy config from each watcher
      @watcher_configs = {}

      # a place to store generated frontend and backend stanzas
      @frontends_cache = {}
      @backends_cache = {}
      @watcher_revisions = {}

      @state_file_path = @opts['state_file_path']
      @state_file_ttl = @opts.fetch('state_file_ttl', DEFAULT_STATE_FILE_TTL).to_i
    end

    def normalize_watcher_provided_config(service_watcher_name, service_watcher_config)
      service_watcher_config = super(service_watcher_name, service_watcher_config)
      defaults = {
        'server_options' => "",
        'server_port_override' => nil,
        'backend' => [],
        'frontend' => [],
      }
      unless service_watcher_config.include?('port')
        log.warn "synapse: service #{service_watcher_name}: haproxy config does not include a port; only backend sections for the service will be created; you must move traffic there manually using configuration in `extra_sections`"
      end
      defaults.merge(service_watcher_config)
    end

    def tick(watchers)
      if (@time % STATE_FILE_UPDATE_INTERVAL) == 0
        update_state_file(watchers)
      end

      @time += 1

      # We potentially have to restart if the restart was rate limited
      # in the original call to update_config
      restart if opts['do_reloads'] && @restart_required
    end

    def update_config(watchers)
      # if we support updating backends, try that whenever possible
      if opts['do_socket']
        opts['socket_file_paths'].each do |socket_path|
          update_backends_at(socket_path, watchers)
        end
      else
        @restart_required = true
      end

      # generate a new config
      new_config = generate_config(watchers)

      # if we write config files, lets do that and then possibly restart
      if opts['do_writes']
        write_config(new_config)
        restart if opts['do_reloads'] && @restart_required
      end
    end

    # generates a new config based on the state of the watchers
    def generate_config(watchers)
      new_config = generate_base_config
      shared_frontend_lines = generate_shared_frontend

      watchers.each do |watcher|
        watcher_config = watcher.config_for_generator[name]
        @watcher_configs[watcher.name] ||= parse_watcher_config(watcher)
        next if watcher_config['disabled']

        regenerate = watcher.revision != @watcher_revisions[watcher.name] ||
                     @frontends_cache[watcher.name].nil? ||
                     @backends_cache[watcher.name].nil?
        if regenerate
          @frontends_cache[watcher.name] = generate_frontend_stanza(watcher, @watcher_configs[watcher.name]['frontend'])
          @backends_cache[watcher.name] = generate_backend_stanza(watcher, @watcher_configs[watcher.name]['backend'])
          @watcher_revisions[watcher.name] = watcher.revision
        end
        new_config << @frontends_cache[watcher.name] << @backends_cache[watcher.name]

        if watcher_config.include?('shared_frontend')
          if opts['shared_frontend'] == nil
            log.warn "synapse: service #{watcher.name} contains a shared frontend section but the base config does not! skipping."
          else
            tabbed_shared_frontend = watcher_config['shared_frontend'].map{|l| "\t#{l}"}
            shared_frontend_lines << validate_haproxy_stanza(
              tabbed_shared_frontend, "frontend", "shared frontend section for #{watcher.name}"
            )
          end
        end
      end
      new_config << shared_frontend_lines.flatten if shared_frontend_lines

      log.debug "synapse: new haproxy config: #{new_config}"
      return new_config.flatten.join("\n")
    end

    # pull out the shared frontend section if any
    def generate_shared_frontend
      return nil unless opts.include?('shared_frontend')
      log.debug "synapse: found a shared frontend section"
      shared_frontend_lines = ["\nfrontend shared-frontend"]
      shared_frontend_lines << validate_haproxy_stanza(opts['shared_frontend'].map{|l| "\t#{l}"}, "frontend", "shared frontend")
      return shared_frontend_lines
    end

    # generates the global and defaults sections of the config file
    def generate_base_config
      base_config = ["# auto-generated by synapse at #{Time.now}\n"]

      %w{global defaults}.each do |section|
        base_config << "#{section}"
        opts[section].each do |option|
          base_config << "\t#{option}"
        end
      end

      if opts['extra_sections']
        opts['extra_sections'].each do |title, section|
          base_config << "\n#{title}"
          section.each do |option|
            base_config << "\t#{option}"
          end
        end
      end

      return base_config
    end

    # split the haproxy config in each watcher into fields applicable in
    # frontend and backend sections
    def parse_watcher_config(watcher)
      config = {}
      watcher_config = watcher.config_for_generator[name]
      %w{frontend backend}.each do |section|
        config[section] = watcher_config[section] || []
      end

      return config
    end

    # generates an individual stanza for a particular watcher
    def generate_frontend_stanza(watcher, config)
      watcher_config = watcher.config_for_generator[name]
      unless watcher_config.has_key?("port")
        log.debug "synapse: not generating frontend stanza for watcher #{watcher.name} because it has no port defined"
        return []
      else
        port = watcher_config['port']
      end

      bind_address = (
        watcher_config['bind_address'] ||
        opts['bind_address'] ||
        DEFAULT_BIND_ADDRESS
      )
      backend_name = watcher_config.fetch('backend_name', watcher.name)

      # Explicit null value passed indicating no port needed
      # For example if the bind_address is a unix port
      bind_port = port.nil? ? '' : ":#{port}"

      bind_line = [
        "\tbind",
        "#{bind_address}#{bind_port}",
        watcher_config['bind_options']
      ].compact.join(' ')

      stanza = [
        "\nfrontend #{watcher.name}",
        config.map {|c| "\t#{c}"},
        bind_line,
        "\tdefault_backend #{backend_name}"
      ]
    end

    def generate_backend_stanza(watcher, config)
      backends = {}

      # The ordering here is important.  First we add all the backends in the
      # disabled state...
      seen.fetch(watcher.name, []).each do |backend_name, backend|
        backends[backend_name] = backend.merge('enabled' => false)
      end

      # ... and then we overwite any backends that the watchers know about,
      # setting the enabled state.
      watcher.backends.each do |backend|
        backend_name = construct_name(backend)
        # If we have information in the state file that allows us to detect
        # server option changes, use that to potentially force a restart
        if backends.has_key?(backend_name)
          old_backend = backends[backend_name]
          if (old_backend.fetch('haproxy_server_options', "") !=
              backend.fetch('haproxy_server_options', ""))
            log.info "synapse: restart required because haproxy_server_options changed for #{backend_name}"
            @restart_required = true
          end
        end
        backends[backend_name] = backend.merge('enabled' => true)
      end

      if watcher.backends.empty?
        log.debug "synapse: no backends found for watcher #{watcher.name}"
      end

      watcher_config = watcher.config_for_generator[name]
      keys = case watcher_config['backend_order']
      when 'asc'
        backends.keys.sort
      when 'desc'
        backends.keys.sort.reverse
      when 'no_shuffle'
        backends.keys
      else
        backends.keys.shuffle
      end

      stanza = [
        "\nbackend #{watcher_config.fetch('backend_name', watcher.name)}",
        config.map {|c| "\t#{c}"},
        keys.map {|backend_name|
          backend = backends[backend_name]
          b = "\tserver #{backend_name} #{backend['host']}:#{backend['port']}"
          unless config.include?('mode tcp')
            b = case watcher_config['cookie_value_method']
            when 'hash'
              b = "#{b} cookie #{Digest::SHA1.hexdigest(backend_name)}"
            else
              b = "#{b} cookie #{backend_name}"
            end
          end
          b = "#{b} #{watcher_config['server_options']}" if watcher_config['server_options']
          b = "#{b} #{backend['haproxy_server_options']}" if backend['haproxy_server_options']
          b = "#{b} disabled" unless backend['enabled']
          b }
      ]
    end

    def talk_to_socket(socket_file_path, command)
      s = UNIXSocket.new(socket_file_path)
      s.write(command)
      s.read
    ensure
      s.close if s
    end

    # tries to set active backends via haproxy's stats socket
    # because we can't add backends via the socket, we might still need to restart haproxy
    def update_backends_at(socket_file_path, watchers)
      # first, get a list of existing servers for various backends
      begin
        stat_command = "show stat -1 4 -1\n"
        info = talk_to_socket(socket_file_path, stat_command)
      rescue StandardError => e
        log.warn "synapse: restart required because socket command #{stat_command} failed "\
                 "with error #{e.inspect}"
        @restart_required = true
        return
      end

      # parse the stats output to get current backends
      cur_backends = {}
      csv = CSV.parse(info, :headers => true)
      re = Regexp.new('^(.+?),(.+?),(?:.*?,){15}(.+?),')

      info.split("\n").each do |line|
        next if line[0] == '#'

        name, addr, state = re.match(line)[1..3]

        next if ['FRONTEND', 'BACKEND'].include?(addr)

        cur_backends[name] ||= {}
        cur_backends[name][addr] = state
      end

      # build a list of backends that should be enabled
      enabled_backends = {}
      watchers.each do |watcher|
        enabled_backends[watcher.name] = Set.new
        next if watcher.backends.empty?
        next if watcher.config_for_generator[name]['disabled']

        unless cur_backends.include? watcher.name
          log.info "synapse: restart required because we added new section #{watcher.name}"
          @restart_required = true
          next
        end

        watcher.backends.each do |backend|
          backend_name = construct_name(backend)
          if cur_backends[watcher.name].include? backend_name
            enabled_backends[watcher.name] << backend_name
          else
            log.info "synapse: restart required because we have a new backend #{watcher.name}/#{backend_name}"
            @restart_required = true
          end
        end
      end

      commands = []

      # actually enable the enabled backends, and disable the disabled ones
      cur_backends.each do |section, backends|
        backends.each do |backend, state|
          if enabled_backends.fetch(section, Set.new).include? backend
            next if state =~ /^UP/
            command = "enable server #{section}/#{backend}"
          else
            command = "disable server #{section}/#{backend}"
          end
          # Batch commands so that we don't need to re-open the connection
          # for every command.
          commands << command
        end
      end

      commands.each_slice(HAPROXY_CMD_BATCH_SIZE) do |batch|
        # actually write the command to the socket
        begin
          output = talk_to_socket(socket_file_path, batch.join(';') + "\n")
        rescue StandardError => e
          log.warn "synapse: restart required because socket command #{batch.join(';')} failed with "\
                   "error #{e.inspect}"
          @restart_required = true
        else
          unless output == "\n" * batch.size
            log.warn "synapse: restart required because socket command #{batch.join(';')} failed with "\
                     "output #{output}"
            @restart_required = true
          end
        end
      end

      log.info "synapse: reconfigured haproxy via #{socket_file_path}"
    end

    # writes the config
    def write_config(new_config)
      begin
        old_config = File.read(opts['config_file_path'])
      rescue Errno::ENOENT => e
        log.info "synapse: could not open haproxy config file at #{opts['config_file_path']}"
        old_config = ""
      end

      if old_config == new_config
        return false
      else
        File.open(opts['config_file_path'],'w') {|f| f.write(new_config)}
        return true
      end
    end

    # restarts haproxy if the time is right
    def restart
      if @time < @next_restart
        log.info "synapse: at time #{@time} waiting until #{@next_restart} to restart"
        return
      end

      @next_restart = @time + @restart_interval
      @next_restart += rand(@restart_jitter * @restart_interval + 1)

      # do the actual restart
      res = `#{opts['reload_command']}`.chomp
      unless $?.success?
        log.error "failed to reload haproxy via #{opts['reload_command']}: #{res}"
        return
      end
      log.info "synapse: restarted haproxy"

      @restart_required = false
    end

    # used to build unique, consistent haproxy names for backends
    def construct_name(backend)
      name = "#{backend['host']}:#{backend['port']}"
      if backend['name'] && !backend['name'].empty?
        name = "#{backend['name']}_#{name}"
      end

      return name
    end

    ######################################
    # methods for managing the state file
    ######################################
    def seen
      # if we don't support the state file, return nothing
      return {} if @state_file_path.nil?

      # if we've never needed the backends, now is the time to load them
      @seen = read_state_file if @seen.nil?

      @seen
    end

    def update_state_file(watchers)
      # if we don't support the state file, do nothing
      return if @state_file_path.nil?

      log.info "synapse: writing state file"
      timestamp = Time.now.to_i

      # Remove stale backends
      seen.each do |watcher_name, backends|
        backends.each do |backend_name, backend|
          ts = backend.fetch('timestamp', 0)
          delta = (timestamp - ts).abs
          if delta > @state_file_ttl
            log.info "synapse: expiring #{backend_name} with age #{delta}"
            backends.delete(backend_name)
          end
        end
      end

      # Remove any services which no longer have any backends
      seen.reject!{|watcher_name, backends| backends.keys.length == 0}

      # Add backends from watchers
      watchers.each do |watcher|
        seen[watcher.name] ||= {}

        watcher.backends.each do |backend|
          backend_name = construct_name(backend)
          seen[watcher.name][backend_name] = backend.merge('timestamp' => timestamp)
        end
      end

      # write the data!
      write_data_to_state_file(seen)
    end

    def read_state_file
      # Some versions of JSON return nil on an empty file ...
      JSON.load(File.read(@state_file_path)) || {}
    rescue StandardError => e
      # It's ok if the state file doesn't exist or contains invalid data
      # The state file will be rebuilt automatically
      {}
    end

    # we do this atomically so the state file is always consistent
    def write_data_to_state_file(data)
      tmp_state_file_path = @state_file_path + ".tmp"
      File.write(tmp_state_file_path, JSON.pretty_generate(data))
      FileUtils.mv(tmp_state_file_path, @state_file_path)
    end
  end
end
