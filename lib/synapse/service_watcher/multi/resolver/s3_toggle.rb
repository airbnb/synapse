require 'synapse/service_watcher/multi/resolver/base'
require 'synapse/log'
require 'synapse/statsd'
require 'synapse/retry_policy'

require 'aws-sdk'
require 'timeout'
require 'thread'
require 'json'

class Synapse::ServiceWatcher::Resolver
  class S3ToggleResolver < BaseResolver
    include Synapse::Logging
    include Synapse::StatsD
    include Synapse::RetryPolicy

    DEFAULT_WATCHER = 'primary'

    @@S3_RETRY_POLICY = {
      'max_attempts' => 3,
      'base_interval' => 10,
      'max_interval' => 180,
      'retriable_errors' => [
        # S3 errors are not included here because the S3 client already includes
        # retrying logic.
        JSON::ParserError,
      ]
    }

    def initialize(opts, watchers)
      super(opts, watchers)

      @watcher_mu = Mutex.new
      @watcher_setting = DEFAULT_WATCHER
      @last_watcher_weights_hash = nil

      @polling_interval = @opts['s3_polling_interval_seconds']

      s3_parts = parse_s3_url(@opts['s3_url'])
      @s3_bucket = s3_parts['bucket']
      @s3_path = s3_parts['path']
    end

    def start
      log.info "synapse: start s3 toggle resolver"

      @should_exit = false
      @thread = Thread.new {
        log.info "synapse: s3 toggle resolver background thread starting"
        last_run = Time.now - rand(@polling_interval)

        until @should_exit
          now = Time.now
          elapsed = now - last_run

          if elapsed >= @polling_interval
            log.info "synapse: s3 resolver reading from s3"
            config_from_s3 = read_s3_file
            set_watcher(config_from_s3)

            last_run = now
          end

          sleep 0.5
        end

        log.info "synapse: s3 toggle resolver background thread exiting normally"
      }
    end

    def stop
      @should_exit = true
      @thread.join unless @thread.nil?
    end

    def merged_backends
      watcher_name = get_watcher
      return @watchers[watcher_name].backends
    end

    def healthy?
      watcher_name = get_watcher
      return @watchers[watcher_name].ping?
    end

    def validate_opts
      %w(method s3_url s3_polling_interval_seconds).each do |opt|
        raise ArgumentError, "s3 toggle resolver expects option #{opt}" unless @opts.has_key?(opt)
      end

      raise ArgumentError, "s3 toggle resolver expects method to be s3_toggle" unless @opts['method'] == 's3_toggle'
      raise ArgumentError, "s3 url should be of form s3://{bucket}/{name}" unless @opts['s3_url'].start_with?('s3://')
      raise ArgumentError, "s3 toggle resolver expects numeric s3_polling_interval_seconds" unless @opts['s3_polling_interval_seconds'].is_a?(Numeric)
      raise ArgumentError, "s3 toggle resolver expects at least 1 watcher" unless @watchers.length > 0
    end

    private

    def get_watcher
      @watcher_mu.synchronize {
        return @watcher_setting
      }
    end

    # pick and set a new watcher, but only if the hash has changed
    def set_watcher(watcher_weights)
      if watcher_weights.hash == @last_watcher_weights_hash
        log.info "synapse: s3 toggle: watcher weights hash does not change; ignoring update"
        statsd_increment('synapse.watcher.multi.resolver.s3_toggle.switch', ['result:skip'])

        return get_watcher
      end

      picked_watcher = pick_watcher(watcher_weights)

      @last_watcher_weights_hash = watcher_weights.hash
      @watcher_mu.synchronize {
        @watcher_setting = picked_watcher
      }

      return picked_watcher
    end

    # randomly pick a watcher based on the provided weights
    def pick_watcher(watcher_weights)
      watcher_weights ||= {}

      # Filter out any watchers that do not exist
      watcher_weights = watcher_weights.select do |watcher, _|
        exists = @watchers.has_key?(watcher)
        unless exists
          log.warn "synapse: s3 toggle: read invalid watcher name #{watcher}"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.unknown_watchers')
        end

        exists
      end

      watcher_name = if watcher_weights.length > 0
        # Pick a watcher randomly by weight.
        total_weight = watcher_weights.values.inject(:+)
        pick = rand(total_weight)
        chosen_watcher = nil

        watcher_weights.each do |key, value|
          if pick < value
            chosen_watcher = key
            break
          else
            pick -= value
          end
        end

        if chosen_watcher.nil?
          log.warn "synapse: s3 toggle: failed to pick a watcher"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.switch', ['result:fail', 'reason:no_choice'])

          DEFAULT_WATCHER
        else
          log.info "synapse: s3 toggle: chose watcher #{chosen_watcher}"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.switch', ['result:success', "watcher:#{chosen_watcher}"])
          chosen_watcher
        end
      else
        log.warn "synapse: s3 toggle: no watchers read, defaulting to primary"
        statsd_increment('synapse.watcher.multi.resolver.s3_toggle.switch', ['result:fail', 'reason:watchers_missing'])

        DEFAULT_WATCHER
      end

      return watcher_name
    end

    def read_s3_file
      s3 = AWS::S3::Client.new

      data =
        begin
          with_retry(@@S3_RETRY_POLICY) do |attempts|
            log.info "synapse: reading s3 toggle file for #{attempts} times"

            resp = s3.get_object(bucket: @s3_bucket, key: @s3_path)
            parsed = JSON.parse(resp.body.read)

            log.info "synapse: read s3 toggle file: #{parsed}"
            parsed
          end
        rescue JSON::ParserError => e
          log.warn "synapse: failed to parse s3 toggle file: #{e}"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.fetch_failure', ["reason:parse_error"])
          {}
        rescue AWS::Errors::Base => e
          log.warn "synapse: failed to fetch s3 toggle file: #{e}"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.fetch_failure', ["reason:s3_error"])
          {}
        end

      return data
    end

    # url = s3://{bucket}/{path}
    def parse_s3_url(url)
      parts = url.partition('s3://')
      raise ArgumentError, "expected url to begin with 's3://' prefix: #{url}" unless parts.length == 3

      bucket, path = parts[2].split('/', 2)
      raise ArgumentError, "expected url to be of format s3://{bucket}/{key}" unless (
          !bucket.nil? &&
          !path.nil? &&
          bucket.length > 0 &&
          path.length > 0)

      return {'bucket' => bucket, 'path' => path}
    end
  end
end
