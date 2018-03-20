require 'datadog/statsd'
require 'synapse/log'

module Synapse
  module StatsD
    def statsd
      @@STATSD ||= StatsD.statsd_for(self.class.name)
    end

    class << self
      include Logging

      @@STATSD_HOST = "localhost"
      @@STATSD_PORT = 8125

      def statsd_for(classname)
        log.debug "synapse: creating statsd client for class '#{classname}' on host '#{@@STATSD_HOST}' port #{@@STATSD_PORT}"
        Datadog::Statsd.new(@@STATSD_HOST, @@STATSD_PORT)
      end

      def configure_statsd(opts)
        @@STATSD_HOST = opts['host'] || @@STATSD_HOST
        @@STATSD_PORT = (opts['port'] || @@STATSD_PORT).to_i
        log.info "synapse: configuring statsd on host '#{@@STATSD_HOST}' port #{@@STATSD_PORT}"
      end
    end
  end
end
