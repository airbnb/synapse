require 'synapse/service_watcher/base/base'
require 'synapse/service_watcher/zookeeper/zookeeper'

require 'concurrent'

class Synapse::ServiceWatcher
  class ZookeeperPollWatcher < ZookeeperWatcher
    def initialize(opts, synapse, reconfigure_callback)
      super(opts, synapse, reconfigure_callback)

      @poll_interval = @discovery['polling_interval_sec'] || 60
      @should_exit = Concurrent::AtomicBoolean.new(false)
    end

    def start(scheduler)
      log.info 'synapse: ZookeeperPollWatcher starting'

      zk_connect do
        reset_schedule = Proc.new {
          discover

          unless @should_exit.true?
            scheduler.post(@polling_interval, reset_schedule) {
              reset_schedule
            }
          end
        }

        scheduler.post(0) {
          reset_schedule
        }
      end
    end

    def stop
      log.warn 'synapse: ZookeeperPollWatcher stopping'

      zk_teardown do
        # Signal to the process that it should not reset.
        @should_exit.make_true
      end
    end

    private

    def validate_discovery_opts
      raise ArgumentError, "zookeeper poll watcher expects zookeeper_poll method" unless @discovery['method'] == 'zookeeper_poll'
      raise ArgumentError, "zookeeper poll watcher expects integer polling_interval_sec >= 0" if (
          @discovery.has_key?('polling_interval_sec') &&
          !(@discovery['polling_interval_sec'].is_a?(Numeric) &&
          @discovery['polling_interval_sec'] >= 0)
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
