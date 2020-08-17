require "synapse/service_watcher/base/poll"

require 'resolv'

class Synapse::ServiceWatcher
  class DnsWatcher < PollWatcher
    def initialize(opts={}, synapse, reconfigure_callback)
      super(opts, synapse, reconfigure_callback)

      @nameserver = @discovery['nameserver']
      @check_interval = @discovery['check_interval'] || 30.0
    end

    def ping?
      !(resolver.getaddresses('airbnb.com').empty?)
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

    def discover
      configure_backends(resolve_servers)
    end

    IP_REGEX = Regexp.union([Resolv::IPv4::Regex, Resolv::IPv6::Regex])

    def resolve_servers
      resolver.tap do |dns|
        resolution = discovery_servers.map do |server|
          if server['host'] =~ IP_REGEX
            addresses = [server['host']]
          else
            addresses = dns.getaddresses(server['host']).map(&:to_s)
          end
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
            'labels' => server['labels'],
          }
        end
      end

      set_backends(new_backends)
    end
  end
end
