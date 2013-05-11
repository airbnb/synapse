require_relative "./base"

require 'thread'
require 'resolv'

module Synapse
  class DnsWatcher < BaseWatcher
    def start
      @backends = @discovery['servers']
      @mutex = Mutex.new
      @check_interval = @discover['check_interval'] || 30.0

      watch
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
        while true
          begin
            start = Time.now
            current_resolution = resolve_servers
            unless last_resolution == current_resolution
              last_resolution = current_resolution
              @mutex.synchronize { @synapse.configure }
            end

            sleep_until_next_check(start)
          rescue => e
            log.warn "Error in watcher thread: #{e.inspect}"
          end
        end
      end
    end

    def sleep_until_next_check(start_time)
      sleep_time = @check_interval - (Time.now - start)
      if sleep_time > 0.0
        sleep(sleep_time)
      end
    end

    def resolve_servers
      @discovery['servers'].map do |server|
        Resolv.getaddress(server['host'])
      end
    rescue => e
      log.warn "Error while resolving host names: #{e.inspect}"
      []
    end
  end
end
