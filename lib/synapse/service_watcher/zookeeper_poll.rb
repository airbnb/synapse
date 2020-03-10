require 'synapse/service_watcher/base'
require 'synapse/service_watcher/zookeeper'

require 'zk'
require 'thread'

class Synapse::ServiceWatcher
  class ZookeeperPollWatcher < ZookeeperWatcher
    def start
      log.info 'synapse: ZookeeperPollWatcher starting'

      @should_exit = false
      @thread = nil
      @poll_interval = @discovery['polling_interval_sec']

      zk_connect do
        @thread = Thread.new {
          log.info 'synapse: zookeeper polling thread started'

          # last_run is shifted by a random jitter in order to spread the first
          # discover call of multiple Synapses. This helps to spread load.
          # As long as the beginning is spread, the future discovers will also
          # be spread.
          last_run = Time.now - rand(@poll_interval)

          until @should_exit
            now = Time.now
            elapsed = now - last_run

            if elapsed >= @poll_interval
              last_run = now
              discover
            end

            sleep 0.5
          end

          log.info 'synapse: zookeeper polling thread exiting normally'
        }
      end
    end

    def stop
      log.warn 'synapse: ZookeeperPollWatcher stopping'

      zk_teardown do
        # Signal to the thread that it should exit, and then wait for it to
        # exit.
        @should_exit = true
        @thread.join unless @thread.nil?
      end
    end

    private

    def validate_discovery_opts
      raise ArgumentError, "zookeeper poll watcher expects zookeeper_poll method" unless @discovery['method'] == 'zookeeper_poll'
      raise ArgumentError, "zookeeper poll watcher expects integer polling_interval_sec >= 0" unless (
          @discovery.has_key?('polling_interval_sec') &&
          @discovery['polling_interval_sec'].is_a?(Numeric) &&
          @discovery['polling_interval_sec'] >= 0
        )
      raise ArgumentError, "missing or invalid zookeeper host for service #{@name}" \
        unless @discovery['hosts']
      raise ArgumentError, "invalid zookeeper path for service #{@name}" \
        unless @discovery['path']
    end

    def discover
      log.info 'synapse: zookeeper polling discover called'
      statsd_increment('synapse.watcher.zookeeper_poll.discover')

      # passing {} disables setting watches
      super({})
    end
  end
end
