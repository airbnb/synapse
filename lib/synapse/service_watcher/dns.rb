require "synapse/service_watcher/base"

require 'thread'
require 'resolv'

module Synapse
  class DnsWatcher < BaseWatcher
    def start
      @check_interval = @discovery['check_interval'] || 30.0
      @nameserver = @discovery['nameserver']

      @watcher = Thread.new do
        watch
      end
    end

    def ping?
      @watcher.alive? && !(resolver.getaddresses('airbnb.com').empty?)
    end

    def discovery_servers
      @discovery['servers']
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'dns'
      raise ArgumentError, "a non-empty list of servers is required" \
        if discovery_servers.empty?
    end

    def watch
      last_resolution = resolve_servers
      configure_backends(last_resolution)
      until @should_exit
        begin
          start = Time.now
          current_resolution = resolve_servers
          unless last_resolution == current_resolution
            last_resolution = current_resolution
            configure_backends(last_resolution)
          end

          sleep_until_next_check(start)
        rescue => e
          log.warn "Error in watcher thread: #{e.inspect}"
          log.warn e.backtrace
        end
      end

      log.info "synapse: dns watcher exited successfully"
    end

    def sleep_until_next_check(start_time)
      sleep_time = @check_interval - (Time.now - start_time)
      if sleep_time > 0.0
        sleep(sleep_time)
      end
    end

    def resolve_servers
      resolver.tap do |dns|
        resolution = discovery_servers.map do |server|
          addresses = dns.getaddresses(server['host']).map(&:to_s)
          [server, addresses.sort]
        end

        return resolution
      end
    rescue => e
      log.warn "Error while resolving host names: #{e.inspect}"
      []
    end

    def resolver
      args = [{:nameserver => @nameserver}] if @nameserver
      Resolv::DNS.open(*args)
    end

    def configure_backends(servers)
      new_backends = servers.flat_map do |(server, addresses)|
        addresses.map do |address|
          {
            'host' => address,
            'port' => server['port'],
            'name' => server['name'],
          }
        end
      end

      if new_backends.empty?
        if @default_servers.empty?
          log.warn "synapse: no backends and no default servers for service #{@name};" \
            " using previous backends: #{@backends.inspect}"
        else
          log.warn "synapse: no backends for service #{@name};" \
            " using default servers: #{@default_servers.inspect}"
          @backends = @default_servers
        end
      else
        log.info "synapse: discovered #{new_backends.length} backends for service #{@name}"
        set_backends(new_backends)
      end

      reconfigure!
    end
  end
end
