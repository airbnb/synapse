require_relative "./base"

require 'thread'
require 'resolv'

module Synapse
  class DnsWatcher < BaseWatcher
    def start
      @check_interval = @discovery['check_interval'] || 30.0
      @nameserver = @discovery['nameserver']

      watch
    end

    def ping?
      !(resolver.getaddresses('airbnb.com').empty?)
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'dns'
      raise ArgumentError, "a non-empty list of servers is required" \
        if @discovery['servers'].empty?
    end

    def watch
      @watcher = Thread.new do
        last_resolution = resolve_servers
        configure_backends(last_resolution)
        while true
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
      end
    end

    def sleep_until_next_check(start_time)
      sleep_time = @check_interval - (Time.now - start_time)
      if sleep_time > 0.0
        sleep(sleep_time)
      end
    end

    def resolve_servers
      resolver.tap do |dns|
        resolution = @discovery['servers'].map do |server|
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
            'name' => "#{server['name']}-#{[address, server['port']].hash}",
            'host' => address,
            'port' => server['port']
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
        @backends = new_backends
      end
      @synapse.reconfigure!
    end
  end
end
