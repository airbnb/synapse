require 'synapse/service_watcher/base'
require 'synapse/service_watcher/dns'
require 'synapse/service_watcher/zookeeper'

require 'thread'

# Watcher for watching Zookeeper for entries containing DNS names that are
# continuously resolved to IP Addresses.  The use case for this watcher is to
# allow services that are addressed by DNS to be reconfigured via Zookeeper
# instead of an update of the synapse config.
#
# The implementation builds on top of the existing DNS and Zookeeper watchers.
# This watcher creates a thread to manage the lifecycle of the DNS and
# Zookeeper watchers.  This thread also publishes messages on a queue to
# indicate that DNS should be re-resolved (after the check interval) or that
# the DNS watcher should be shut down.  The Zookeeper watcher waits for changes
# in backends from zookeeper and publishes those changes on an internal queue
# consumed by the DNS watcher.  The DNS watcher blocks on this queue waiting
# for messages indicating that new servers are available, the check interval
# has passed (triggering a re-resolve), or that the watcher should shut down.
# The DNS watcher is responsible for the actual reconfiguring of backends.
module Synapse
  class ZookeeperDnsWatcher < BaseWatcher

    module Messages
      class InvalidMessageError < RuntimeError; end

      class NewServers < Struct.new(:servers); end
      class CheckInterval; end
      class StopWatcher; end

      STOP_WATCHER_MESSAGE = StopWatcher.new
      CHECK_INTERVAL_MESSAGE = CheckInterval.new
    end

    class Dns < Synapse::DnsWatcher

      attr_accessor :discovery_servers

      def initialize(opts={}, synapse, message_queue)
        @message_queue = message_queue

        super(opts, synapse)
      end

      def stop
        @message_queue.push(Messages::STOP_WATCHER_MESSAGE)
      end

      def watch
        last_resolution = nil
        while true
          message = @message_queue.pop

          case message
          when Messages::StopWatcher
            break
          when Messages::NewServers
            self.discovery_servers = message.servers
          when Messages::CheckInterval
            # Proceed to re-resolve the DNS
          else
            raise Messages::InvalidMessageError,
              "Received unrecognized message: #{message.inspect}"
          end

          # Empty servers means we haven't heard back from ZK yet
          unless self.discovery_servers.nil? || self.discovery_servers.empty?
            current_resolution = resolve_servers
            unless last_resolution == current_resolution
              last_resolution = current_resolution
              configure_backends(last_resolution)
            end
          end
        end
      end

      private

      def validate_discovery_opts
      end
    end

    class Zookeeper < Synapse::ZookeeperWatcher
      def initialize(opts={}, synapse, message_queue)
        super(opts, synapse)

        @message_queue = message_queue
      end

      def reconfigure!
        # push the new backends onto the queue
        @message_queue.push(Messages::NewServers.new(@backends))
      end

      private

      def validate_discovery_opts
      end
    end

    def start
      dns_discovery_opts = @discovery.select do |k,_|
        k == 'nameserver' || k == 'default_servers'
      end

      zookeeper_discovery_opts = @discovery.select do |k,_|
        k == 'hosts' || k == 'path'
      end


      @check_interval = @discovery['check_interval'] || 30.0

      @message_queue = Queue.new

      @dns = Dns.new(
        mk_child_watcher_opts(dns_discovery_opts),
        @synapse,
        @message_queue
      )

      @zk = Zookeeper.new(
        mk_child_watcher_opts(zookeeper_discovery_opts),
        @synapse,
        @message_queue
      )

      @watcher = Thread.new do
        @zk.start
        @dns.start

        until @should_exit
          sleep @check_interval

          @message_queue.push(Messages::CHECK_INTERVAL_MESSAGE)
        end
      end
    end

    def ping?
      @dns.ping? && @zk.ping?
    end

    def stop
      super

      @dns.stop
      @zk.stop
    end

    def backends
      @dns.backends
    end

    private

    def validate_discovery_opts
      unless @discovery['method'] == 'zookeeper_dns'
        raise ArgumentError, "invalid discovery method #{@discovery['method']}"
      end

      unless @discovery['hosts']
        raise ArgumentError, "missing or invalid zookeeper host for service #{@name}"
      end

      unless @discovery['path']
        raise ArgumentError, "invalid zookeeper path for service #{@name}"
      end
    end

    def mk_child_watcher_opts(discovery_opts)
      {
        'name' => @name,
        'haproxy' => @haproxy,
        'discovery' => discovery_opts,
      }
    end

    def reconfigure!
    end
  end
end

