require 'fileutils'
require 'json'
require 'socket'

module Synapse
  class Haproxy
    include Logging
    attr_reader :opts, :name

    # these come from the documentation for haproxy 1.5
    # http://haproxy.1wt.eu/download/1.5/doc/configuration.txt
    @@section_fields = {
      "backend" => [
        "acl",
        "appsession",
        "balance",
        "bind-process",
        "block",
        "compression",
        "contimeout",
        "cookie",
        "default-server",
        "description",
        "disabled",
        "dispatch",
        "enabled",
        "errorfile",
        "errorloc",
        "errorloc302",
        "errorloc303",
        "force-persist",
        "fullconn",
        "grace",
        "hash-type",
        "http-check disable-on-404",
        "http-check expect",
        "http-check send-state",
        "http-request",
        "http-response",
        "http-reuse",
        "id",
        "ignore-persist",
        "log",
        "mode",
        "option abortonclose",
        "option accept-invalid-http-response",
        "option allbackups",
        "option allredisp",
        "option checkcache",
        "option forceclose",
        "option forwardfor",
        "option http-no-delay",
        "option http-pretend-keepalive",
        "option http-server-close",
        "option httpchk",
        "option httpclose",
        "option httplog",
        "option http_proxy",
        "option independent-streams",
        "option lb-agent-chk",
        "option ldap-check",
        "option log-health-checks",
        "option mysql-check",
        "option pgsql-check",
        "option nolinger",
        "option originalto",
        "option persist",
        "option redispatch",
        "option redis-check",
        "option smtpchk",
        "option splice-auto",
        "option splice-request",
        "option splice-response",
        "option srvtcpka",
        "option ssl-hello-chk",
        "option tcp-check",
        "option tcp-smart-connect",
        "option tcpka",
        "option tcplog",
        "option transparent",
        "persist rdp-cookie",
        "redirect",
        "redisp",
        "redispatch",
        "reqadd",
        "reqallow",
        "reqdel",
        "reqdeny",
        "reqiallow",
        "reqidel",
        "reqideny",
        "reqipass",
        "reqirep",
        "reqisetbe",
        "reqitarpit",
        "reqpass",
        "reqrep",
        "reqsetbe",
        "reqtarpit",
        "retries",
        "rspadd",
        "rspdel",
        "rspdeny",
        "rspidel",
        "rspideny",
        "rspirep",
        "rsprep",
        "server",
        "source",
        "srvtimeout",
        "stats admin",
        "stats auth",
        "stats enable",
        "stats hide-version",
        "stats http-request",
        "stats realm",
        "stats refresh",
        "stats scope",
        "stats show-desc",
        "stats show-legends",
        "stats show-node",
        "stats uri",
        "stick match",
        "stick on",
        "stick store-request",
        "stick store-response",
        "stick-table",
        "tcp-check connect",
        "tcp-check expect",
        "tcp-check send",
        "tcp-check send-binary",
        "tcp-request content",
        "tcp-request inspect-delay",
        "tcp-response content",
        "tcp-response inspect-delay",
        "timeout check",
        "timeout connect",
        "timeout contimeout",
        "timeout http-keep-alive",
        "timeout http-request",
        "timeout queue",
        "timeout server",
        "timeout srvtimeout",
        "timeout tarpit",
        "timeout tunnel",
        "transparent",
        "use-server"
      ],
      "defaults" => [
        "backlog",
        "balance",
        "bind-process",
        "clitimeout",
        "compression",
        "contimeout",
        "cookie",
        "default-server",
        "default_backend",
        "disabled",
        "enabled",
        "errorfile",
        "errorloc",
        "errorloc302",
        "errorloc303",
        "fullconn",
        "grace",
        "hash-type",
        "http-check disable-on-404",
        "http-check send-state",
        "http-reuse",
        "log",
        "maxconn",
        "mode",
        "monitor-net",
        "monitor-uri",
        "option abortonclose",
        "option accept-invalid-http-request",
        "option accept-invalid-http-response",
        "option allbackups",
        "option allredisp",
        "option checkcache",
        "option clitcpka",
        "option contstats",
        "option dontlog-normal",
        "option dontlognull",
        "option forceclose",
        "option forwardfor",
        "option http-no-delay",
        "option http-pretend-keepalive",
        "option http-server-close",
        "option http-use-proxy-header",
        "option httpchk",
        "option httpclose",
        "option httplog",
        "option http_proxy",
        "option independent-streams",
        "option lb-agent-chk",
        "option ldap-check",
        "option log-health-checks",
        "option log-separate-errors",
        "option logasap",
        "option mysql-check",
        "option pgsql-check",
        "option nolinger",
        "option originalto",
        "option persist",
        "option redispatch",
        "option redis-check",
        "option smtpchk",
        "option socket-stats",
        "option splice-auto",
        "option splice-request",
        "option splice-response",
        "option srvtcpka",
        "option ssl-hello-chk",
        "option tcp-check",
        "option tcp-smart-accept",
        "option tcp-smart-connect",
        "option tcpka",
        "option tcplog",
        "option transparent",
        "persist rdp-cookie",
        "rate-limit sessions",
        "redisp",
        "redispatch",
        "retries",
        "source",
        "srvtimeout",
        "stats auth",
        "stats enable",
        "stats hide-version",
        "stats realm",
        "stats refresh",
        "stats scope",
        "stats show-desc",
        "stats show-legends",
        "stats show-node",
        "stats uri",
        "timeout check",
        "timeout client",
        "timeout clitimeout",
        "timeout connect",
        "timeout contimeout",
        "timeout http-keep-alive",
        "timeout http-request",
        "timeout queue",
        "timeout server",
        "timeout srvtimeout",
        "timeout tarpit",
        "timeout tunnel",
        "transparent",
        "unique-id-format",
        "unique-id-header"
      ],
      "frontend" => [
        "acl",
        "backlog",
        "bind",
        "bind-process",
        "block",
        "capture cookie",
        "capture request header",
        "capture response header",
        "clitimeout",
        "compression",
        "default_backend",
        "description",
        "disabled",
        "enabled",
        "errorfile",
        "errorloc",
        "errorloc302",
        "errorloc303",
        "force-persist",
        "grace",
        "http-request",
        "http-response",
        "id",
        "ignore-persist",
        "log",
        "maxconn",
        "mode",
        "monitor fail",
        "monitor-net",
        "monitor-uri",
        "option accept-invalid-http-request",
        "option clitcpka",
        "option contstats",
        "option dontlog-normal",
        "option dontlognull",
        "option forceclose",
        "option forwardfor",
        "option http-no-delay",
        "option http-pretend-keepalive",
        "option http-server-close",
        "option http-use-proxy-header",
        "option httpclose",
        "option httplog",
        "option http_proxy",
        "option independent-streams",
        "option log-separate-errors",
        "option logasap",
        "option nolinger",
        "option originalto",
        "option socket-stats",
        "option splice-auto",
        "option splice-request",
        "option splice-response",
        "option tcp-smart-accept",
        "option tcpka",
        "option tcplog",
        "rate-limit sessions",
        "redirect",
        "reqadd",
        "reqallow",
        "reqdel",
        "reqdeny",
        "reqiallow",
        "reqidel",
        "reqideny",
        "reqipass",
        "reqirep",
        "reqisetbe",
        "reqitarpit",
        "reqpass",
        "reqrep",
        "reqsetbe",
        "reqtarpit",
        "rspadd",
        "rspdel",
        "rspdeny",
        "rspidel",
        "rspideny",
        "rspirep",
        "rsprep",
        "tcp-request connection",
        "tcp-request content",
        "tcp-request inspect-delay",
        "timeout client",
        "timeout clitimeout",
        "timeout http-keep-alive",
        "timeout http-request",
        "timeout tarpit",
        "unique-id-format",
        "unique-id-header",
        "use_backend"
      ],
      "listen" => [
        "acl",
        "appsession",
        "backlog",
        "balance",
        "bind",
        "bind-process",
        "block",
        "capture cookie",
        "capture request header",
        "capture response header",
        "clitimeout",
        "compression",
        "contimeout",
        "cookie",
        "default-server",
        "default_backend",
        "description",
        "disabled",
        "dispatch",
        "enabled",
        "errorfile",
        "errorloc",
        "errorloc302",
        "errorloc303",
        "force-persist",
        "fullconn",
        "grace",
        "hash-type",
        "http-check disable-on-404",
        "http-check expect",
        "http-check send-state",
        "http-request",
        "http-response",
        "http-reuse",
        "id",
        "ignore-persist",
        "log",
        "maxconn",
        "mode",
        "monitor fail",
        "monitor-net",
        "monitor-uri",
        "option abortonclose",
        "option accept-invalid-http-request",
        "option accept-invalid-http-response",
        "option allbackups",
        "option allredisp",
        "option checkcache",
        "option clitcpka",
        "option contstats",
        "option dontlog-normal",
        "option dontlognull",
        "option forceclose",
        "option forwardfor",
        "option http-no-delay",
        "option http-pretend-keepalive",
        "option http-server-close",
        "option http-use-proxy-header",
        "option httpchk",
        "option httpclose",
        "option httplog",
        "option http_proxy",
        "option independent-streams",
        "option lb-agent-chk",
        "option ldap-check",
        "option log-health-checks",
        "option log-separate-errors",
        "option logasap",
        "option mysql-check",
        "option pgsql-check",
        "option nolinger",
        "option originalto",
        "option persist",
        "option redispatch",
        "option redis-check",
        "option smtpchk",
        "option socket-stats",
        "option splice-auto",
        "option splice-request",
        "option splice-response",
        "option srvtcpka",
        "option ssl-hello-chk",
        "option tcp-check",
        "option tcp-smart-accept",
        "option tcp-smart-connect",
        "option tcpka",
        "option tcplog",
        "option transparent",
        "persist rdp-cookie",
        "rate-limit sessions",
        "redirect",
        "redisp",
        "redispatch",
        "reqadd",
        "reqallow",
        "reqdel",
        "reqdeny",
        "reqiallow",
        "reqidel",
        "reqideny",
        "reqipass",
        "reqirep",
        "reqisetbe",
        "reqitarpit",
        "reqpass",
        "reqrep",
        "reqsetbe",
        "reqtarpit",
        "retries",
        "rspadd",
        "rspdel",
        "rspdeny",
        "rspidel",
        "rspideny",
        "rspirep",
        "rsprep",
        "server",
        "source",
        "srvtimeout",
        "stats admin",
        "stats auth",
        "stats enable",
        "stats hide-version",
        "stats http-request",
        "stats realm",
        "stats refresh",
        "stats scope",
        "stats show-desc",
        "stats show-legends",
        "stats show-node",
        "stats uri",
        "stick match",
        "stick on",
        "stick store-request",
        "stick store-response",
        "stick-table",
        "tcp-check connect",
        "tcp-check expect",
        "tcp-check send",
        "tcp-check send-binary",
        "tcp-request connection",
        "tcp-request content",
        "tcp-request inspect-delay",
        "tcp-response content",
        "tcp-response inspect-delay",
        "timeout check",
        "timeout client",
        "timeout clitimeout",
        "timeout connect",
        "timeout contimeout",
        "timeout http-keep-alive",
        "timeout http-request",
        "timeout queue",
        "timeout server",
        "timeout srvtimeout",
        "timeout tarpit",
        "timeout tunnel",
        "transparent",
        "unique-id-format",
        "unique-id-header",
        "use_backend",
        "use-server"
      ]
    }

    def initialize(opts)
      super()

      %w{global defaults reload_command}.each do |req|
        raise ArgumentError, "haproxy requires a #{req} section" if !opts.has_key?(req)
      end

      req_pairs = {
        'do_writes' => 'config_file_path',
        'do_socket' => 'socket_file_path',
        'do_reloads' => 'reload_command'}

      req_pairs.each do |cond, req|
        if opts[cond]
          raise ArgumentError, "the `#{req}` option is required when `#{cond}` is true" unless opts[req]
        end
      end

      @opts = opts
      @name = 'haproxy'

      @opts['do_writes'] = true unless @opts.key?('do_writes')
      @opts['do_socket'] = true unless @opts.key?('do_socket')
      @opts['do_reloads'] = true unless @opts.key?('do_reloads')

      # how to restart haproxy
      @restart_interval = @opts.fetch('restart_interval', 2).to_i
      @restart_jitter = @opts.fetch('restart_jitter', 0).to_f
      @restart_required = true

      # virtual clock bookkeeping for controlling how often haproxy restarts
      @time = 0
      @next_restart = @time

      # a place to store the parsed haproxy config from each watcher
      @watcher_configs = {}

      @state_file_path = @opts['state_file_path']
      @state_file_ttl = @opts.fetch('state_file_ttl', 60 * 60 * 24).to_i
      @seen = {}

      unless @state_file_path.nil?
        begin
          @seen = JSON.load(File.read(@state_file_path))
        rescue StandardError => e
          # It's ok if the state file doesn't exist
        end
      end
    end

    def tick(watchers)
      if @time % 60 == 0 && !@state_file_path.nil?
        update_state_file(watchers)
      end

      @time += 1

      # We potentially have to restart if the restart was rate limited
      # in the original call to update_config
      restart if @opts['do_reloads'] && @restart_required
    end

    def update_config(watchers)
      # if we support updating backends, try that whenever possible
      if @opts['do_socket']
        update_backends(watchers)
      else
        @restart_required = true
      end

      # generate a new config
      new_config = generate_config(watchers)

      # if we write config files, lets do that and then possibly restart
      if @opts['do_writes']
        write_config(new_config)
        restart if @opts['do_reloads'] && @restart_required
      end
    end

    # generates a new config based on the state of the watchers
    def generate_config(watchers)
      new_config = generate_base_config
      shared_frontend_lines = generate_shared_frontend

      watchers.each do |watcher|
        @watcher_configs[watcher.name] ||= parse_watcher_config(watcher)
        new_config << generate_frontend_stanza(watcher, @watcher_configs[watcher.name]['frontend'])
        new_config << generate_backend_stanza(watcher, @watcher_configs[watcher.name]['backend'])
        if watcher.haproxy.include?('shared_frontend')
          if @opts['shared_frontend'] == nil
            log.warn "synapse: service #{watcher.name} contains a shared frontend section but the base config does not! skipping."
          else
            shared_frontend_lines << validate_haproxy_stanza(watcher.haproxy['shared_frontend'].map{|l| "\t#{l}"}, "frontend", "shared frontend section for #{watcher.name}")
          end
        end
      end
      new_config << shared_frontend_lines.flatten if shared_frontend_lines

      log.debug "synapse: new haproxy config: #{new_config}"
      return new_config.flatten.join("\n")
    end

    # pull out the shared frontend section if any
    def generate_shared_frontend
      return nil unless @opts.include?('shared_frontend')
      log.debug "synapse: found a shared frontend section"
      shared_frontend_lines = ["\nfrontend shared-frontend"]
      shared_frontend_lines << validate_haproxy_stanza(@opts['shared_frontend'].map{|l| "\t#{l}"}, "frontend", "shared frontend")
      return shared_frontend_lines
    end

    # generates the global and defaults sections of the config file
    def generate_base_config
      base_config = ["# auto-generated by synapse at #{Time.now}\n"]

      %w{global defaults}.each do |section|
        base_config << "#{section}"
        @opts[section].each do |option|
          base_config << "\t#{option}"
        end
      end

      if @opts['extra_sections']
        @opts['extra_sections'].each do |title, section|
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
      %w{frontend backend}.each do |section|
        config[section] = watcher.haproxy[section] || []

        # copy over the settings from the 'listen' section that pertain to section
        config[section].concat(
          watcher.haproxy['listen'].select {|setting|
            parsed_setting = setting.strip.gsub(/\s+/, ' ').downcase
            @@section_fields[section].any? {|field| parsed_setting.start_with?(field)}
          })

        # pick only those fields that are valid and warn about the invalid ones
        config[section] = validate_haproxy_stanza(config[section], section, watcher.name)
      end

      return config
    end

    def validate_haproxy_stanza(stanza, stanza_type, service_name)
      return stanza.select {|setting|
        parsed_setting = setting.strip.gsub(/\s+/, ' ').downcase
        if @@section_fields[stanza_type].any? {|field| parsed_setting.start_with?(field)}
          true
        else
          log.warn "synapse: service #{service_name} contains invalid #{stanza_type} setting: '#{setting}', discarding"
          false
        end
      }
    end

    # generates an individual stanza for a particular watcher
    def generate_frontend_stanza(watcher, config)
      unless watcher.haproxy.has_key?("port")
        log.debug "synapse: not generating frontend stanza for watcher #{watcher.name} because it has no port defined"
        return []
      end

      stanza = [
        "\nfrontend #{watcher.name}",
        config.map {|c| "\t#{c}"},
        "\tbind #{ watcher.haproxy['bind_address'] || @opts['bind_address'] || 'localhost'}:#{watcher.haproxy['port']}",
        "\tdefault_backend #{watcher.haproxy.fetch('backend_name', watcher.name)}"
      ]
    end

    def generate_backend_stanza(watcher, config)
      backends = {}

      # The ordering here is important.  First we add all the backends in the
      # disabled state...
      @seen.fetch(watcher.name, []).each do |backend_name, backend|
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

      keys = case watcher.haproxy['backend_order']
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
        "\nbackend #{watcher.haproxy.fetch('backend_name', watcher.name)}",
        config.map {|c| "\t#{c}"},
        keys.map {|backend_name|
          backend = backends[backend_name]
          b = "\tserver #{backend_name} #{backend['host']}:#{backend['port']}"
          b = "#{b} cookie #{backend_name}" unless config.include?('mode tcp')
          b = "#{b} #{watcher.haproxy['server_options']}" if watcher.haproxy['server_options']
          if backend.has_key?('weight')
            # Check if server_options already contains weight, is so log a warning
            if watcher.haproxy['server_options'].include? 'weight'
              log.warn "synapse: weight is defined by server_options and by nerve"
            end
            weight = backend['weight'].to_i
            b = "#{b} weight #{weight}"
          end
          b = "#{b} #{backend['haproxy_server_options']}" if backend['haproxy_server_options']
          b = "#{b} disabled" unless backend['enabled']
          b }
      ]
    end

    # tries to set active backends via haproxy's stats socket
    # because we can't add backends via the socket, we might still need to restart haproxy
    def update_backends(watchers)
      # first, get a list of existing servers for various backends
      begin
        s = UNIXSocket.new(@opts['socket_file_path'])
        s.write("show stat\n")
        info = s.read()
      rescue StandardError => e
        log.warn "synapse: unhandled error reading stats socket: #{e.inspect}"
        @restart_required = true
        return
      end

      # parse the stats output to get current backends
      cur_backends = {}
      info.split("\n").each do |line|
        next if line[0] == '#'

        parts = line.split(',')
        next if ['FRONTEND', 'BACKEND'].include?(parts[1])

        cur_backends[parts[0]] ||= []
        cur_backends[parts[0]] << parts[1]
      end

      # build a list of backends that should be enabled
      enabled_backends = {}
      watchers.each do |watcher|
        enabled_backends[watcher.name] = []
        next if watcher.backends.empty?

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

      # actually enable the enabled backends, and disable the disabled ones
      cur_backends.each do |section, backends|
        backends.each do |backend|
          if enabled_backends.fetch(section, []).include? backend
            command = "enable server #{section}/#{backend}\n"
          else
            command = "disable server #{section}/#{backend}\n"
          end

          # actually write the command to the socket
          begin
            s = UNIXSocket.new(@opts['socket_file_path'])
            s.write(command)
            output = s.read()
          rescue StandardError => e
            log.warn "synapse: unknown error writing to socket"
            @restart_required = true
          else
            unless output == "\n"
              log.warn "synapse: socket command #{command} failed: #{output}"
              @restart_required = true
            end
          end
        end
      end

      log.info "synapse: reconfigured haproxy"
    end

    # writes the config
    def write_config(new_config)
      begin
        old_config = File.read(@opts['config_file_path'])
      rescue Errno::ENOENT => e
        log.info "synapse: could not open haproxy config file at #{@opts['config_file_path']}"
        old_config = ""
      end

      if old_config == new_config
        return false
      else
        File.open(@opts['config_file_path'],'w') {|f| f.write(new_config)}
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
        name = "#{name}_#{backend['name']}"
      end

      return name
    end

    def update_state_file(watchers)
      log.info "synapse: writing state file"

      timestamp = Time.now.to_i

      # Remove stale backends
      @seen.each do |watcher_name, backends|
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
      @seen = @seen.reject{|watcher_name, backends| backends.keys.length == 0}

      # Add backends from watchers
      watchers.each do |watcher|
        unless @seen.key?(watcher.name)
          @seen[watcher.name] = {}
        end

        watcher.backends.each do |backend|
          backend_name = construct_name(backend)
          @seen[watcher.name][backend_name] = backend.merge('timestamp' => timestamp)
        end
      end

      # Atomically write new state file
      tmp_state_file_path = @state_file_path + ".tmp"
      File.write(tmp_state_file_path, JSON.pretty_generate(@seen))
      FileUtils.mv(tmp_state_file_path, @state_file_path)
    end
  end
end
