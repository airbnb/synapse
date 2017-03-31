require 'synapse/config_generator/base'

require 'fileutils'
require 'json'
require 'socket'
require 'digest/sha1'
require 'set'

class Synapse::ConfigGenerator
  class Haproxy < BaseGenerator
    include Synapse::Logging

    NAME = 'haproxy'.freeze

    HAPROXY_CMD_BATCH_SIZE = 4

    # these come from the documentation for haproxy (1.5 and 1.6)
    # http://haproxy.1wt.eu/download/1.5/doc/configuration.txt
    # http://haproxy.1wt.eu/download/1.6/doc/configuration.txt
    SECTION_FIELDS = {
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
        "email-alert from",
        "email-alert level",
        "email-alert mailers",
        "email-alert myhostname",
        "email-alert to",
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
        "http-send-name-header",
        "http-reuse",
        "http-send-name-header",
        "id",
        "ignore-persist",
        "load-server-state-from-file",
        "log",
        "log-tag",
        "max-keep-alive-queue",
        "mode",
        "no log",
        "no option abortonclose",
        "no option accept-invalid-http-response",
        "no option allbackups",
        "no option allredisp",
        "no option checkcache",
        "no option forceclose",
        "no option forwardfor",
        "no option http-buffer-request",
        "no option http-keep-alive",
        "no option http-no-delay",
        "no option http-pretend-keepalive",
        "no option http-server-close",
        "no option http-tunnel",
        "no option httpchk",
        "no option httpclose",
        "no option httplog",
        "no option http_proxy",
        "no option independent-streams",
        "no option lb-agent-chk",
        "no option ldap-check",
        "no option external-check",
        "no option log-health-checks",
        "no option mysql-check",
        "no option pgsql-check",
        "no option nolinger",
        "no option originalto",
        "no option persist",
        "no option pgsql-check",
        "no option prefer-last-server",
        "no option redispatch",
        "no option redis-check",
        "no option smtpchk",
        "no option splice-auto",
        "no option splice-request",
        "no option splice-response",
        "no option srvtcpka",
        "no option ssl-hello-chk",
        "no option tcp-check",
        "no option tcp-smart-connect",
        "no option tcpka",
        "no option tcplog",
        "no option transparent",
        "option abortonclose",
        "option accept-invalid-http-response",
        "option allbackups",
        "option allredisp",
        "option checkcache",
        "option forceclose",
        "option forwardfor",
        "option http-buffer-request",
        "option http-keep-alive",
        "option http-no-delay",
        "option http-pretend-keepalive",
        "option http-server-close",
        "option http-tunnel",
        "option httpchk",
        "option httpclose",
        "option httplog",
        "option http_proxy",
        "option independent-streams",
        "option lb-agent-chk",
        "option ldap-check",
        "option external-check",
        "option log-health-checks",
        "option mysql-check",
        "option pgsql-check",
        "option nolinger",
        "option originalto",
        "option persist",
        "option pgsql-check",
        "option prefer-last-server",
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
        "external-check command",
        "external-check path",
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
        "server-state-file-name",
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
        "timeout server-fin",
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
        "email-alert from",
        "email-alert level",
        "email-alert mailers",
        "email-alert myhostname",
        "email-alert to",
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
        "load-server-state-from-file",
        "log",
        "log-format",
        "log-format-sd",
        "log-tag",
        "max-keep-alive-queue",
        "maxconn",
        "mode",
        "monitor-net",
        "monitor-uri",
        "no log",
        "no option abortonclose",
        "no option accept-invalid-http-request",
        "no option accept-invalid-http-response",
        "no option allbackups",
        "no option allredisp",
        "no option checkcache",
        "no option clitcpka",
        "no option contstats",
        "no option dontlog-normal",
        "no option dontlognull",
        "no option forceclose",
        "no option forwardfor",
        "no option http-buffer-request",
        "no option http-ignore-probes",
        "no option http-keep-alive",
        "no option http-no-delay",
        "no option http-pretend-keepalive",
        "no option http-server-close",
        "no option http-tunnel",
        "no option http-use-proxy-header",
        "no option httpchk",
        "no option httpclose",
        "no option httplog",
        "no option http_proxy",
        "no option independent-streams",
        "no option lb-agent-chk",
        "no option ldap-check",
        "no option external-check",
        "no option log-health-checks",
        "no option log-separate-errors",
        "no option logasap",
        "no option mysql-check",
        "no option pgsql-check",
        "no option nolinger",
        "no option originalto",
        "no option persist",
        "no option pgsql-check",
        "no option prefer-last-server",
        "no option redispatch",
        "no option redis-check",
        "no option smtpchk",
        "no option socket-stats",
        "no option splice-auto",
        "no option splice-request",
        "no option splice-response",
        "no option srvtcpka",
        "no option ssl-hello-chk",
        "no option tcp-check",
        "no option tcp-smart-accept",
        "no option tcp-smart-connect",
        "no option tcpka",
        "no option tcplog",
        "no option transparent",
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
        "option http-buffer-request",
        "option http-ignore-probes",
        "option http-keep-alive",
        "option http-no-delay",
        "option http-pretend-keepalive",
        "option http-server-close",
        "option http-tunnel",
        "option http-use-proxy-header",
        "option httpchk",
        "option httpclose",
        "option httplog",
        "option http_proxy",
        "option independent-streams",
        "option lb-agent-chk",
        "option ldap-check",
        "option external-check",
        "option log-health-checks",
        "option log-separate-errors",
        "option logasap",
        "option mysql-check",
        "option pgsql-check",
        "option nolinger",
        "option originalto",
        "option persist",
        "option pgsql-check",
        "option prefer-last-server",
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
        "external-check command",
        "external-check path",
        "persist rdp-cookie",
        "rate-limit sessions",
        "redisp",
        "redispatch",
        "retries",
        "server-state-file-name",
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
        "timeout client-fin",
        "timeout clitimeout",
        "timeout connect",
        "timeout contimeout",
        "timeout http-keep-alive",
        "timeout http-request",
        "timeout queue",
        "timeout server",
        "timeout server-fin",
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
        "declare capture",
        "default_backend",
        "description",
        "disabled",
        "email-alert from",
        "email-alert level",
        "email-alert mailers",
        "email-alert myhostname",
        "email-alert to",
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
        "log-format",
        "log-format-sd",
        "log-tag",
        "maxconn",
        "mode",
        "monitor fail",
        "monitor-net",
        "monitor-uri",
        "no log",
        "no option accept-invalid-http-request",
        "no option clitcpka",
        "no option contstats",
        "no option dontlog-normal",
        "no option dontlognull",
        "no option forceclose",
        "no option forwardfor",
        "no option http-buffer-request",
        "no option http-ignore-probes",
        "no option http-keep-alive",
        "no option http-no-delay",
        "no option http-pretend-keepalive",
        "no option http-server-close",
        "no option http-tunnel",
        "no option http-use-proxy-header",
        "no option httpclose",
        "no option httplog",
        "no option http_proxy",
        "no option independent-streams",
        "no option log-separate-errors",
        "no option logasap",
        "no option nolinger",
        "no option originalto",
        "no option socket-stats",
        "no option splice-auto",
        "no option splice-request",
        "no option splice-response",
        "no option tcp-smart-accept",
        "no option tcpka",
        "no option tcplog",
        "option accept-invalid-http-request",
        "option clitcpka",
        "option contstats",
        "option dontlog-normal",
        "option dontlognull",
        "option forceclose",
        "option forwardfor",
        "option http-buffer-request",
        "option http-ignore-probes",
        "option http-keep-alive",
        "option http-no-delay",
        "option http-pretend-keepalive",
        "option http-server-close",
        "option http-tunnel",
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
        "tcp-request connection",
        "tcp-request content",
        "tcp-request inspect-delay",
        "timeout client",
        "timeout client-fin",
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
        "declare capture",
        "default-server",
        "default_backend",
        "description",
        "disabled",
        "dispatch",
        "email-alert from",
        "email-alert level",
        "email-alert mailers",
        "email-alert myhostname",
        "email-alert to",
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
        "http-send-name-header",
        "http-reuse",
        "http-send-name-header",
        "id",
        "ignore-persist",
        "load-server-state-from-file",
        "log",
        "log-format",
        "log-format-sd",
        "log-tag",
        "max-keep-alive-queue",
        "maxconn",
        "mode",
        "monitor fail",
        "monitor-net",
        "monitor-uri",
        "no log",
        "no option abortonclose",
        "no option accept-invalid-http-request",
        "no option accept-invalid-http-response",
        "no option allbackups",
        "no option allredisp",
        "no option checkcache",
        "no option clitcpka",
        "no option contstats",
        "no option dontlog-normal",
        "no option dontlognull",
        "no option forceclose",
        "no option forwardfor",
        "no option http-buffer-request",
        "no option http-ignore-probes",
        "no option http-keep-alive",
        "no option http-no-delay",
        "no option http-pretend-keepalive",
        "no option http-server-close",
        "no option http-tunnel",
        "no option http-use-proxy-header",
        "no option httpchk",
        "no option httpclose",
        "no option httplog",
        "no option http_proxy",
        "no option independent-streams",
        "no option lb-agent-chk",
        "no option ldap-check",
        "no option external-check",
        "no option log-health-checks",
        "no option log-separate-errors",
        "no option logasap",
        "no option mysql-check",
        "no option pgsql-check",
        "no option nolinger",
        "no option originalto",
        "no option persist",
        "no option pgsql-check",
        "no option prefer-last-server",
        "no option redispatch",
        "no option redis-check",
        "no option smtpchk",
        "no option socket-stats",
        "no option splice-auto",
        "no option splice-request",
        "no option splice-response",
        "no option srvtcpka",
        "no option ssl-hello-chk",
        "no option tcp-check",
        "no option tcp-smart-accept",
        "no option tcp-smart-connect",
        "no option tcpka",
        "no option tcplog",
        "no option transparent",
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
        "option http-buffer-request",
        "option http-ignore-probes",
        "option http-keep-alive",
        "option http-no-delay",
        "option http-pretend-keepalive",
        "option http-server-close",
        "option http-tunnel",
        "option http-use-proxy-header",
        "option httpchk",
        "option httpclose",
        "option httplog",
        "option http_proxy",
        "option independent-streams",
        "option lb-agent-chk",
        "option ldap-check",
        "option external-check",
        "option log-health-checks",
        "option log-separate-errors",
        "option logasap",
        "option mysql-check",
        "option pgsql-check",
        "option nolinger",
        "option originalto",
        "option persist",
        "option pgsql-check",
        "option prefer-last-server",
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
        "external-check command",
        "external-check path",
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
        "server-state-file-name",
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
        "timeout client-fin",
        "timeout clitimeout",
        "timeout connect",
        "timeout contimeout",
        "timeout http-keep-alive",
        "timeout http-request",
        "timeout queue",
        "timeout server",
        "timeout server-fin",
        "timeout srvtimeout",
        "timeout tarpit",
        "timeout tunnel",
        "transparent",
        "unique-id-format",
        "unique-id-header",
        "use_backend",
        "use-server"
      ]
    }.freeze

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
        'listen' => [],
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

        # copy over the settings from the 'listen' section that pertain to section
        config[section].concat(
          watcher_config['listen'].select {|setting|
            parsed_setting = setting.strip.gsub(/\s+/, ' ').downcase
            SECTION_FIELDS[section].any? {|field| parsed_setting.start_with?(field)}
          })

        # pick only those fields that are valid and warn about the invalid ones
        config[section] = validate_haproxy_stanza(config[section], section, watcher.name)
      end

      return config
    end

    def validate_haproxy_stanza(stanza, stanza_type, service_name)
      return stanza.select {|setting|
        parsed_setting = setting.strip.gsub(/\s+/, ' ').downcase
        if SECTION_FIELDS[stanza_type].any? {|field| parsed_setting.start_with?(field)}
          true
        else
          log.warn "synapse: service #{service_name} contains invalid #{stanza_type} setting: '#{setting}', discarding"
          false
        end
      }
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
        stat_command = "show stat\n"
        info = talk_to_socket(socket_file_path, stat_command)
      rescue StandardError => e
        log.warn "synapse: restart required because socket command #{stat_command} failed "\
                 "with error #{e.inspect}"
        @restart_required = true
        return
      end

      # parse the stats output to get current backends
      cur_backends = {}
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
