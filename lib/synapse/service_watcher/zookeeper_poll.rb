require 'synapse/service_watcher/base'
require 'synapse/service_watcher/zookeeper'

require 'zk'
require 'thread'
require 'timeout'

class Synapse::ServiceWatcher
  class ZookeeperPollWatcher < ZookeeperWatcher
    def start
      log.info 'synapse: ZookeeperPollWatcher starting'

      @thread = nil
      @mutex = Mutex.new
      @mutex.lock

      zk_connect do
        @thread = Thread.new {
          log.info 'synapse: zookeeper polling thread started'

          should_exit = false
          until should_exit
            discover

            sleep_duration = @discovery['polling_interval_sec']
            log.info "synapse: zookeeper polling thread sleeping for #{sleep_duration} seconds"

            # Awake either when
            # (1) Mutex is released, which occurs in #stop. This means we
            #     should exit the thread, which will occur on the next
            #     iteration.
            # (2) sleep_duration seconds has passed.
            begin
              Timeout::timeout(sleep_duration) {
                mutex.lock
                should_exit = true
              }
            rescue Timeout::Error
              # do nothing, this just means we should proceed to the next loop
            end
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
        @mutex.unlock unless @mutex.nil?
        @thread.join unless @thread.nil?
      end
    end

    private

    def validate_discovery_opts
      raise ArgumentError, "zookeeper poll watcher expects zookeeper_poll method" unless @discovery['method'] == 'zookeeper_poll'
      raise ArgumentError, "zookeeper poll watcher expects integer polling_interval_sec >= 0" unless (
          @discovery.has_key?('polling_interval_sec') &&
          @discovery['polling_interval_sec'].is_a?(Integer) &&
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

      super(false)
    end
  end
end
