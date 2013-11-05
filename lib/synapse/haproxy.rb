require 'socket'
require 'digest'

module Synapse
  class Haproxy
    attr_reader :opts

    # these come from the documentation for haproxy 1.5
    # http://haproxy.1wt.eu/download/1.5/doc/configuration.txt
    section_fields = {
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
        "id",
        "ignore-persist",
        "log",
        "mode",
        "option abortonclose",
        "option accept-invalid-http-response",
        "option allbackups",
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
        "log",
        "maxconn",
        "mode",
        "monitor-net",
        "monitor-uri",
        "option abortonclose",
        "option accept-invalid-http-request",
        "option accept-invalid-http-response",
        "option allbackups",
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

      # how to restart haproxy
      @restart_interval = 2
      @restart_required = true
      @last_restart = Time.new(0)
    end

    def update_config(watchers)
      # if we support updating backends, try that whenever possible
      if @opts['do_socket']
        update_backends(watchers) unless @restart_required
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

      new_config << watchers.map {|w| generate_listen_stanza(w)}
      new_config << watchers.map {|w| generate_backend_stanza(w)}

      log.debug "synapse: new haproxy config: #{new_config}"
      return new_config.flatten.join("\n")
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

    # generates an individual stanza for a particular watcher
    def generate_listen_stanza(watcher)
      unless watcher.haproxy.has_key?("port")
        log.debug "synapse: not generating listen stanza for watcher #{watcher.name} because it has no port defined"
        return []
      end

      stanza = ["\nlisten #{watcher.name}_in localhost:#{watcher.haproxy['port']}"]

      # add the config lines relevant to a listen section
      watcher.haproxy['config'].each do |line|
        section_fields['listen'].each do |fieldname|
          if line.strip.index(fieldname) == 0
            stanza << "\t#{line}"
            break
          end
        end
      end

      stanza << "\tdefault_backend #{watcher.name}"

      return stanza
    end

    def generate_backend_stanza(watcher)
      if watcher.backends.empty?
        log.warn "synapse: no backends found for watcher #{watcher.name}"
        return []
      end

      stanza = ["\nbackend #{watcher.name}"]

      # add the config lines relevant to a listen section
      watcher.haproxy['config'].each do |line|
        section_fields['backend'].each do |fieldname|
          if line.strip.index(fieldname) == 0
            stanza << "\t#{line}"
            break
          end
        end
      end

      watcher.backends.shuffle.each do |backend|
        backend_name = construct_name(backend)
        stanza << "\tserver #{backend_name} #{backend['host']}:#{backend['port']} #{watcher.haproxy['server_options']}"
      end
      return stanza
    end

    # tries to set active backends via haproxy's stats socket
    # because we can't add backends via the socket, we might still need to restart haproxy
    def update_backends(watchers)
      # first, get a list of existing servers for various backends
      begin
        s = UNIXSocket.new(@opts['socket_file_path'])
        s.write('show stat;')
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
          log.debug "synapse: restart required because we added new section #{watcher.name}"
          @restart_required = true
          return
        end

        watcher.backends.each do |backend|
          backend_name = construct_name(backend)
          unless cur_backends[watcher.name].include? backend_name
            log.debug "synapse: restart required because we have a new backend #{watcher.name}/#{backend_name}"
            @restart_required = true
            return
          end

          enabled_backends[watcher.name] << backend_name
        end
      end

      # actually enable the enabled backends, and disable the disabled ones
      cur_backends.each do |section, backends|
        backends.each do |backend|
          if enabled_backends[section].include? backend
            command = "enable server #{section}/#{backend};"
          else
            command = "disable server #{section}/#{backend};"
          end

          # actually write the command to the socket
          begin
            s = UNIXSocket.new(@opts['socket_file_path'])
            s.write(command)
            output = s.read()
          rescue StandardError => e
            log.warn "synapse: unknown error writing to socket"
            @restart_required = true
            return
          else
            unless output == "\n"
              log.warn "synapse: socket command #{command} failed: #{output}"
              @restart_required = true
              return
            end
          end
        end
      end
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

    # restarts haproxy
    def restart
      # sleep if we restarted too recently
      delay = (@last_restart - Time.now) + @restart_interval
      sleep(delay) if delay > 0

      # do the actual restart
      res = `#{opts['reload_command']}`.chomp
      raise "failed to reload haproxy via #{opts['reload_command']}: #{res}" unless $?.success?

      @last_restart = Time.now()
      @restart_required = false
    end

    # used to build unique, consistent haproxy names for backends
    def construct_name(backend)
      address_digest = Digest::SHA256.hexdigest(backend['host'])[0..7]
      return "#{backend['name']}:#{backend['port']}_#{address_digest}"
    end
  end
end
