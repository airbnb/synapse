require 'synapse/config_generator/base'

require 'fileutils'
require 'json'
require 'socket'
require 'digest/sha1'
require 'set'
require 'hashdiff'

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
    # It's unclear how many servers HAProxy can have in one backend, but 65k
    # should be enough for anyone right (famous last words)?
    MAX_SERVER_ID = (2**16 - 1).freeze

    attr_reader :server_id_map, :state_cache

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

      @state_cache = HaproxyState.new(
        @opts['state_file_path'],
        @opts.fetch('state_file_ttl', DEFAULT_STATE_FILE_TTL).to_i,
        self
      )

      # For giving consistent orders, even if they are random
      @server_order_seed = @opts.fetch('server_order_seed', rand(2000)).to_i
      @max_server_id = @opts.fetch('max_server_id', MAX_SERVER_ID).to_i
      # Map of backend names -> hash of HAProxy server names -> puids
      # (server->id aka "name") to their proxy unique id (server->puid aka "id")
      @server_id_map = Hash.new{|h,k| h[k] = {}}
      # Map of backend names -> hash of HAProxy server puids -> names
      # (server->puid aka "id") to their name (server->id aka "name")
      @id_server_map = Hash.new{|h,k| h[k] = {}}

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

    def update_state_file(watchers)
      @state_cache.update_state_file(watchers)
    end

    # generates a new config based on the state of the watchers
    def generate_config(watchers)
      new_config = generate_base_config
      shared_frontend_lines = generate_shared_frontend

      watchers.each do |watcher|
        watcher_config = watcher.config_for_generator[name]
        next if watcher_config.nil? || watcher_config.empty? || watcher_config['disabled']
        @watcher_configs[watcher.name] = parse_watcher_config(watcher)

        # if watcher_config is changed, trigger restart
        config_diff = HashDiff.diff(@state_cache.config_for_generator(watcher.name), watcher_config)
        if !config_diff.empty?
          log.info "synapse: restart required because config_for_generator changed. before: #{@state_cache.config_for_generator(watcher.name)}, after: #{watcher_config}"
          @restart_required = true
        end

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
      @state_cache.backends(watcher.name).each do |backend_name, backend|
        backends[backend_name] = backend.merge('enabled' => false)
        # We remember the haproxy_server_id from a previous reload here.
        # Note though that if live servers below define haproxy_server_id
        # that overrides the remembered value
        @server_id_map[watcher.name][backend_name] ||= backends[backend_name]['haproxy_server_id']
        @id_server_map[watcher.name][@server_id_map[watcher.name][backend_name]] = backend_name if @server_id_map[watcher.name][backend_name]
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

          if(@opts['use_nerve_weights'] && old_backend.fetch('weight', "") != backend.fetch('weight', ""))
            log.info "synapse: restart required because weight changed for #{backend_name}"
            @restart_required = true
          end
        end

        backends[backend_name] = backend.merge('enabled' => true)

        # If the the registry defines the haproxy_server_id that must be preferred.
        # Note that the order here is important, because if haproxy_server_options
        # does define an id, then we will write that out below, so that must be what
        # is in the id_map as well.
        @server_id_map[watcher.name][backend_name] = backend['haproxy_server_id'].to_i if backend['haproxy_server_id']
        server_opts = backend['haproxy_server_options'].split(' ') if backend['haproxy_server_options'].is_a? String
        @server_id_map[watcher.name][backend_name] = server_opts[server_opts.index('id') + 1].to_i if server_opts && server_opts.include?('id')
        @id_server_map[watcher.name][@server_id_map[watcher.name][backend_name]] = backend_name
      end

      # Now that we know the maximum possible existing haproxy_server_id for
      # this backend, we can set any that don't exist yet.
      watcher.backends.each do |backend|
        backend_name = construct_name(backend)
        @server_id_map[watcher.name][backend_name] ||= find_next_id(watcher.name, backend_name)
        @id_server_map[watcher.name][@server_id_map[watcher.name][backend_name]] = backend_name
      end
      # Remove any servers that don't exist anymore from the server_id_map
      # to control memory growth
      @server_id_map[watcher.name].keep_if { |server_name| backends.has_key?(server_name) }
      @id_server_map[watcher.name].keep_if { |_, server_name| @server_id_map[watcher.name][server_name] }

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
        backends.keys.shuffle(random: Random.new(@server_order_seed))
      end

      stanza = [
        "\nbackend #{watcher_config.fetch('backend_name', watcher.name)}",
        config.map {|c| "\t#{c}"},
        keys.map {|backend_name|
          backend = backends[backend_name]
          b = "\tserver #{backend_name} #{backend['host']}:#{backend['port']}"

          # Again, if the registry defines an id, we can't set it.
          has_id = backend['haproxy_server_options'].split(' ').include?('id') if backend['haproxy_server_options'].is_a? String
          if (!has_id && @server_id_map[watcher.name][backend_name])
            b = "#{b} id #{@server_id_map[watcher.name][backend_name]}"
          end

          unless config.include?('mode tcp')
            b = case watcher_config['cookie_value_method']
            when 'hash'
              b = "#{b} cookie #{Digest::SHA1.hexdigest(backend_name)}"
            else
              b = "#{b} cookie #{backend_name}"
            end
          end

          if @opts['use_nerve_weights'] && backend['weight'] && (backend['weight'].is_a? Integer)
            clean_server_options = remove_weight_option watcher_config['server_options']
            clean_haproxy_server_options = remove_weight_option backend['haproxy_server_options']
            if clean_server_options != watcher_config['server_options']
                log.warn "synapse: weight is defined in both server_options and nerve. nerve weight will take precedence"
            end
            if clean_haproxy_server_options != backend['haproxy_server_options']
                log.warn "synapse: weight is defined in both haproxy_server_options and nerve. nerve weight will take precedence"
            end
            b = "#{b} #{clean_server_options}" if clean_server_options
            b = "#{b} #{clean_haproxy_server_options}" if clean_haproxy_server_options

            weight = backend['weight'].to_i
            b = "#{b} weight #{weight}".squeeze(" ")
          else
            b = "#{b} #{watcher_config['server_options']}" if watcher_config['server_options'].is_a? String
            b = "#{b} #{backend['haproxy_server_options']}" if backend['haproxy_server_options'].is_a? String
          end
          b = "#{b} disabled" unless backend['enabled']
          b }
      ]
    end

    def remove_weight_option(server_options)
      if server_options.is_a? String
        server_options = server_options.sub /weight +[0-9]+/,''
      end
      server_options
    end

    def find_next_id(watcher_name, backend_name)
      probe = nil
      if @server_id_map[watcher_name].size >= @max_server_id
        log.error "synapse: ran out of server ids for #{watcher_name}, if you need more increase the max_server_id option"
        return probe
      end

      probe = 1

      while @id_server_map[watcher_name].include?(probe)
        probe = (probe % @max_server_id) + 1
      end

      probe
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
        tmp_file_path = "#{opts['config_file_path']}.tmp"
        File.write(tmp_file_path, new_config)
        FileUtils.mv(tmp_file_path, opts['config_file_path'])
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
    class HaproxyState
      include Synapse::Logging

      # TODO: enable version in the Haproxy Cache File
      KEY_WATCHER_CONFIG_FOR_GENERATOR = "watcher_config_for_generator"
      NON_BACKENDS_KEYS = [KEY_WATCHER_CONFIG_FOR_GENERATOR]

      def initialize(state_file_path, state_file_ttl, haproxy)
        @state_file_path = state_file_path
        @state_file_ttl = state_file_ttl
        @haproxy = haproxy
      end

      def backends(watcher_name)
        if seen.key?(watcher_name)
          seen[watcher_name].select { |section, data| !NON_BACKENDS_KEYS.include?(section) }
        else
          {}
        end
      end

      def config_for_generator(watcher_name)
        cache_config = {}
        if seen.key?(watcher_name) && seen[watcher_name].key?(KEY_WATCHER_CONFIG_FOR_GENERATOR)
          cache_config = seen[watcher_name][KEY_WATCHER_CONFIG_FOR_GENERATOR]
        end

        cache_config
      end

      def update_state_file(watchers)
        # if we don't support the state file, do nothing
        return if @state_file_path.nil?

        log.info "synapse: writing state file"
        timestamp = Time.now.to_i

        # Remove stale backends
        seen.each do |watcher_name, data|
          backends(watcher_name).each do |backend_name, backend|
            ts = backend.fetch('timestamp', 0)
            delta = (timestamp - ts).abs
            if delta > @state_file_ttl
              log.info "synapse: expiring #{backend_name} with age #{delta}"
              data.delete(backend_name)
            end
          end
        end

        # Remove any services which no longer have any backends
        seen.reject!{|watcher_name, data| backends(watcher_name).keys.length == 0}

        # Add backends and config from watchers
        watchers.each do |watcher|
          seen[watcher.name] ||= {}

          watcher.backends.each do |backend|
            backend_name = @haproxy.construct_name(backend)
            data = {
              'timestamp' => timestamp,
            }
            server_id = @haproxy.server_id_map[watcher.name][backend_name].to_i
            if server_id && server_id > 0 && server_id <= MAX_SERVER_ID
              data['haproxy_server_id'] = server_id
            end

            seen[watcher.name][backend_name] = data.merge(backend)
          end

          # Add config for generator from watcher
          if watcher.config_for_generator.key?(@haproxy.name)
            seen[watcher.name][KEY_WATCHER_CONFIG_FOR_GENERATOR] =
              watcher.config_for_generator[@haproxy.name]
          end
        end

        # write the data!
        write_data_to_state_file(seen)
      end

      private

      def seen
        # if we don't support the state file, return nothing
        return {} if @state_file_path.nil?

        # if we've never needed the backends, now is the time to load them
        @seen = read_state_file if @seen.nil?

        @seen
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
end
