require 'synapse/service_watcher/base/base'

require 'concurrent'

class Synapse::ServiceWatcher
  class PollWatcher < BaseWatcher
    def initialize(opts={}, synapse, reconfigure_callback)
      super(opts, synapse, reconfigure_callback)

      @check_interval = @discovery['check_interval'] || 15.0
      @should_exit = Concurrent::AtomicBoolean.new(false)
    end

    def start(scheduler)
      reset_schedule = Proc.new {
        discover

        unless @should_exit.true?
          scheduler.post(@check_interval) {
            reset_schedule
          }
        end
      }

      scheduler.post(0) {
        reset_schedule
      }
    end

    def stop
      @should_exit.make_true
    end

    def discover
      log.info "base poll watcher discover"
    end
  end
end
