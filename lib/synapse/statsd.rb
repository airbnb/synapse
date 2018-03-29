require 'datadog/statsd'
require 'synapse/log'

module Synapse
  module StatsD
    def statsd
      @@STATSD ||= StatsD.statsd_for(self.class.name)
    end

    def statsd_increment(key, tags = [])
      statsd.increment(key, tags: tags, sample_rate: sample_rate_for(key))
    end

    def statsd_time(key, tags = [])
      statsd.time(key, tags: tags, sample_rate: sample_rate_for(key)) do
        yield
      end
    end

    class << self
      include Logging

      @@STATSD_HOST = "localhost"
      @@STATSD_PORT = 8125
      @@STATSD_SAMPLE_RATE = {}

      def statsd_for(classname)
        log.debug "synapse: creating statsd client for class '#{classname}' on host '#{@@STATSD_HOST}' port #{@@STATSD_PORT}"
        Datadog::Statsd.new(@@STATSD_HOST, @@STATSD_PORT)
      end

      def configure_statsd(opts)
        @@STATSD_HOST = opts['host'] || @@STATSD_HOST
        @@STATSD_PORT = (opts['port'] || @@STATSD_PORT).to_i
        @@STATSD_SAMPLE_RATE = opts['sample_rate'] || {}
        log.info "synapse: configuring statsd on host '#{@@STATSD_HOST}' port #{@@STATSD_PORT}"
      end
    end

    private

    def sample_rate_for(key)
      rate = @@STATSD_SAMPLE_RATE[key]
      rate.nil? ? 1 : rate
    end
  end
end
