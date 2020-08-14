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

        # Schedule the next task until we should exit
        unless @should_exit.true?
          scheduler.post(@check_interval) {
            reset_schedule.call
          }
        end
      }

      # Execute the first discover immediately
      scheduler.post(0) {
        reset_schedule.call
      }
    end

    def stop
      @should_exit.make_true
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method '#{@discovery['method']}' for poll watcher" \
        unless @discovery['method'] == 'poll'

      log.warn "synapse: warning: a stub watcher with no default servers is pretty useless" if @default_servers.empty?
    end

    def discover
      log.info "base poll watcher discover"
    end
  end
end
