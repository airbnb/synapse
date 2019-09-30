module Synapse
  module RetryPolicy
    include Synapse::StatsD

    def with_retry(options = {}, &callback)
      max_attempts = options['max_attempts'] || 1
      max_delay = options['max_delay'] || 3600
      base_interval = options['base_interval'] || 0
      max_interval = options['max_interval'] || 0
      retriable_errors = Array(options['retriable_errors'] || StandardError)
      if max_attempts <= 0
        raise ArgumentError, "max_attempts must be greater than 0"
      end
      if base_interval < 0
        raise ArgumentError, "base_interval cannot be negative"
      end
      if max_interval < 0
        raise ArgumentError, "max_interval cannot be negative"
      end
      if base_interval > max_interval
        raise ArgumentError, "base_interval cannot be greater than max_interval"
      end
      if callback.nil?
        raise ArgumentError, "callback cannot be nil"
      end
      attempts = 0
      start_time = Time.now
      begin
        attempts += 1
        return callback.call(attempts)
      rescue *retriable_errors => error
        if attempts >= max_attempts
          statsd_increment('synapse.retry', ['op:raise_max_attempts'])
          raise error
        end
        if (Time.now - start_time) >= max_delay
          statsd_increment('synapse.retry', ['op:raise_max_delay'])
          raise error
        end
        statsd_increment('synapse.retry', ['op:retry_after_sleep'])
        sleep get_retry_interval(base_interval, max_interval, attempts)
        retry
      end
    end

    def get_retry_interval(base_interval, max_interval, attempts)
      retry_interval = base_interval * (2 ** (attempts - 1)) # exponetial back-off
      retry_interval = retry_interval * (0.5 * (1 + rand())) # randomize
      [[retry_interval, base_interval].max, max_interval].min # regularize
    end
  end
end

