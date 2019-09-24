module Synapse
  module RetryPolicy
    def with_retry(options = {}, &callback)
      max_attempts = options[:max_attempts] || 1
      base_interval = options[:base_interval] || 0
      max_interval = options[:max_interval] || 0
      retriable_errors = Array(options[:retriable_errors] || StandardError)
      if max_attempts <= 0
        raise ":max_attempts must be greater than 0"
      end
      if base_interval > max_interval
        raise ":base_interval cannot be greater than :max_interval."
      end
      if callback.nil?
        raise "callback cannot be nil"
      end

      attempts = 0
      start_time = Time.now
      begin
        attempts += 1
        return callback.call(attempts)
      rescue *retriable_errors => error
        if attempts >= max_attempts
          raise error
        end
        sleep get_retry_interval(base_interval, max_interval, attempts, Time.now - start_time)
        retry
      end
    end

    def get_retry_interval(base_interval, max_interval, attempts, elapsed)
      [[base_interval * (2 ** (attempts - 1)) - elapsed, base_interval].max, max_interval].min
    end
  end
end

