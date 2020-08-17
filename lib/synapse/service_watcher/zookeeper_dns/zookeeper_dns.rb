require 'synapse/service_watcher/base/poll'
require 'synapse/service_watcher/dns/dns'
require 'synapse/service_watcher/zookeeper/zookeeper'

require 'concurrent'

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
class Synapse::ServiceWatcher
  class ZookeeperDnsWatcher < PollWatcher

    # Valid messages that can be passed through the internal message queue
    module Messages
      class InvalidMessageError < RuntimeError; end

      # Indicates new servers identified by DNS names to be resolved.  This is
      # sent from Zookeeper on events that modify the ZK node. The payload is
      # an array of hashes containing {'host', 'port', 'name'}
      class NewServers < Struct.new(:servers); end

      # Indicates that DNS should be re-resolved.  This is sent by the
      # ZookeeperDnsWatcher thread every check_interval seconds to cause a
      # refresh of the IP addresses.
      class CheckInterval; end

      # Saved instances of message types with contents that cannot vary.  This
      # reduces object allocation.
      CHECK_INTERVAL_MESSAGE = CheckInterval.new
    end

    class Dns < Synapse::ServiceWatcher::DnsWatcher

      # Overrides the discovery_servers method on the parent class
      attr_accessor :discovery_servers

      def initialize(opts={}, parent=nil, synapse, reconfigure_callback, message_queue)
        @message_queue = message_queue
        @parent = parent
        @last_resolution = Concurrent::Atom.new(nil)

        super(opts, synapse, reconfigure_callback)
      end

      def discover
        # Blocks on message queue, the message will be a signal to stop
        # watching, to check a new set of servers from ZK, or to re-resolve
        # the DNS (triggered every check_interval seconds)
        message = @message_queue.pop

        log.debug "synapse: received message #{message.inspect}"

        case message
        when Messages::NewServers
          self.discovery_servers = message.servers
        when Messages::CheckInterval
        # Proceed to re-resolve the DNS
        else
          raise Messages::InvalidMessageError,
                "Received unrecognized message: #{message.inspect}"
        end

        # Empty servers means we haven't heard back from ZK yet or ZK is
        # empty.  This should only occur if we don't get results from ZK
        # within check_interval seconds or if ZK is empty.
        if self.discovery_servers.nil? || self.discovery_servers.empty?
          log.warn "synapse: no backends for service #{@name}"
        else
          # Resolve DNS names with the nameserver
          current_resolution = resolve_servers
          unless @last_resolution.value == current_resolution
            last_resolution.reset(current_resolution)
            configure_backends(current_resolution)

            # Propagate revision updates down to ZookeeperDnsWatcher, so
            # that stanza cache can work properly.
            @revision += 1
            @parent.reconfigure! unless @parent.nil?
          end
        end
      end

      private

      # Validation is skipped as it has already occurred in the parent watcher
      def validate_discovery_opts
      end
    end

    def start(scheduler)
      @check_interval = @discovery['check_interval'] || 30.0
      @message_queue = Queue.new

      @dns = make_dns_watcher(@message_queue)
      @zk = make_zookeeper_watcher(@message_queue)

      @zk.start(scheduler)
      @dns.start(scheduler)

      super(scheduler)
    end

    def ping?
      @watcher.alive? && @dns.ping? && @zk.ping?
    end

    def stop
      super

      @dns.stop
      @zk.stop
    end

    def backends
      @dns.backends
    end

    # Override reconfigure! as this class should not explicitly reconfigure
    # synapse. The `Dns` class (@dns) actually calls the reconfigure for
    # Synapse, because it inherits the default implementation.
    def reconfigure!
      @revision += 1
    end

    private

    def discover
      if @message_queue.empty?
        @message_queue.push(Messages::CHECK_INTERVAL_MESSAGE)
      end
    end

    def make_dns_watcher(queue)
      dns_discovery_opts = @discovery.select do |k,_|
        k == 'nameserver' || k == 'label_filter'
      end

      Dns.new(
        mk_child_watcher_opts(dns_discovery_opts),
        self,
        @synapse,
        @reconfigure_callback,
        queue
      )
    end

    def make_zookeeper_watcher(queue)
      zookeeper_discovery_opts = @discovery.select do |k,_|
        k == 'hosts' || k == 'path' || k == 'label_filter'
      end
      zookeeper_discovery_opts['method'] = 'zookeeper'

      Synapse::ServiceWatcher::ZookeeperWatcher.new(
        mk_child_watcher_opts(zookeeper_discovery_opts),
        @synapse,
        ->(backends, *args) { update_dns_watcher(queue, backends) },
      )
    end

    def update_dns_watcher(queue, backends)
      queue.push(Messages::NewServers.new(backends))
      reconfigure!
    end

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

    # Method to generate a full config for the children (Dns and Zookeeper)
    # watchers
    #
    # Notes on passing in the default_servers:
    #
    #   Setting the default_servers here allows the Zookeeper watcher to return
    #   a list of backends based on the default servers when it fails to find
    #   any matching servers.  These are passed on as the discovered backends
    #   to the DNS watcher, which will then watch them as normal for DNS
    #   changes.  The default servers can also come into play if none of the
    #   hostnames from Zookeeper resolve to addresses in the DNS watcher.  This
    #   should generally result in the expected behavior, but caution should be
    #   taken when deciding that this is the desired behavior.
    def mk_child_watcher_opts(discovery_opts)
      {
        'name' => @name,
        'discovery' => discovery_opts,
        'default_servers' => @default_servers,
        'use_previous_backends' => @use_previous_backends,
      }
    end
  end
end
