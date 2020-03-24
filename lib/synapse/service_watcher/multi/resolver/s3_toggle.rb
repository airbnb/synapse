require 'synapse/service_watcher/multi/resolver/base'
require 'synapse/log'
require 'synapse/statsd'

require 'aws-sdk'
require 'timeout'
require 'thread'
require 'yaml'

class Synapse::ServiceWatcher::Resolver
  class S3ToggleResolver < BaseResolver
    include Synapse::Logging
    include Synapse::StatsD

    # The S3 file schema, which is validated in validate_s3_file_schema, is YAML
    # of the form:
    #
    # ---
    # primary: weight
    # watcher_name: weight
    # ...
    #
    # The keys refer to the watchers as defined in the Synapse configuration.
    # `primary` is the default watcher, defined by the `discovery` section.
    # All other watchers are defined under `discovery_multi.watchers`.
    # The weight is a non-negative integer value which determines how likely it
    # is for the watcher to get chosen.
    DEFAULT_WATCHER = 'primary'.freeze

    @@s3_watcher = nil

    def initialize(opts, watchers, notification_callback)
      super(opts, watchers, notification_callback)

      @watcher_mu = Mutex.new
      @watcher_setting = DEFAULT_WATCHER
      @last_watcher_weights_hash = nil

      @polling_interval = @opts['s3_polling_interval_seconds']

      s3_parts = parse_s3_url(@opts['s3_url'])
      @s3_bucket = s3_parts['bucket']
      @s3_path = s3_parts['path']

      @@s3_watcher ||= BackgroundS3Poller.new
    end

    def start
      log.info "synapse: s3 toggle resolver: starting"

      @@s3_watcher.add_path(@s3_bucket, @s3_path, @polling_interval,
                            -> (path){ set_watcher(path) })
    end

    def stop
      log.warn "synapse: s3 toggle resolver: stopping"
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
      raise ArgumentError, "s3 toggle resolver expects numeric s3_polling_interval_seconds > 0" unless @opts['s3_polling_interval_seconds'].is_a?(Numeric) && @opts['s3_polling_interval_seconds'] > 0
      raise ArgumentError, "s3 toggle resolver expects at least 1 watcher" unless @watchers.length > 0
    end

    private

    def set_watcher(w)
      new_watcher = false

      @watcher_mu.synchronize {
        current = @watcher_setting

        unless current == w
          @watcher_setting = w
          new_watcher = true
        end
      }

      send_notification if new_watcher
    end

    def get_watcher
      @watcher_mu.synchronize {
        return @watcher_setting
      }
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

    # Polls multiple S3 files with different polling intervals.
    # Calls a callback with the file contents after each read.
    class BackgroundS3Poller
      @@s3_client = AWS::S3::Client.new

      def initialize()
        @mu = Mutex.new
        @thread = nil
        @paths = {}
      end

      def add_path(bucket, key, polling_interval, callback)
        path_key = "#{bucket}/#{key}:#{polling_interval}s"

        @mu.synchronize {
          path_config = @paths[path_key]

          if path_config.nil?
            path_config = {:bucket => bucket,
                           :key => key,
                           :polling_interval => polling_interval,
                           :last_run => Time.now - rand(polling_interval),
                           :picked_watcher => nil,
                           :last_content_hash => nil,
                           :callbacks => []}
          end

          path_config[:callbacks] << callback
          @paths[path_key] = path_config
        }
      end

      def start
        return unless @thread.nil?

        @should_exit = false
        @thread = Thread.new {
          log.info "synapse: s3 toggle resolver: background thread starting"

          while true
            @mu.synchronize {
              return if @should_exit
              update_s3_picks
            }

            sleep 1
          end

          log.info "synapse: s3 toggle resolver: background thread exiting normally"
        }
      end

      def stop
        @mu.synchronize { @should_exit = true }
        @thread.join unless @thread.nil?
        @thread = nil
      end

      private

      def update_s3_picks
        @paths.each_value do |path_data|
          if Time.now - path_data[:last_run] >= path_data[:polling_interval]
            path_data_from_s3 = read_s3_file(path_data[:bucket], path_data[:key])
            picked_watcher = set_watcher(path_data, path_data_from_s3)


            path_data[:callbacks].each do |cb|
              cb.call(picked_watcher)
            end

            path_data[:last_run] = Time.now
          end
        end
      end

      # pick and set a new watcher, but only if the hash has changed
      def set_watcher(path_data, watcher_weights)
        if watcher_weights.hash == path_data[:last_content_hash]
          log.info "synapse: s3 toggle resolver: watcher weights hash does not change; ignoring update"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.switch', ['result:skip'])

          return path_data[:picked_watcher]
        end

        picked_watcher = pick_watcher(watcher_weights)
        if picked_watcher.nil?
          return path_data[:picked_watcher]
        end

        path_data[:picked_watcher] = picked_watcher
        path_data[:last_content_hash] = watcher_weights.hash

        return picked_watcher
      end

      # randomly pick a watcher based on the provided weights.
      # if it returns nil, it means it could not pick.
      def pick_watcher(watcher_weights)
        if watcher_weights.nil?
          log.warn "synapse: s3 toggle resolver: received nil watcher weights, not picking"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.switch', ['result:fail', 'reason:nil_weights'])

          return nil
        end

        watcher_name = nil
        total_weight = watcher_weights.values.inject(0, :+)

        if total_weight == 0
          log.warn "synapse: s3 toggle resolver: sum of all weights equal 0, not picking"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.switch', ['result:fail', 'reason:zero_sum'])
        elsif watcher_weights.length == 0
          log.warn "synapse: s3 toggle resolver: no watchers read, failed to pick a watcher"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.switch', ['result:fail', 'reason:watchers_missing'])
        else
          pick = rand(total_weight)

          watcher_weights.each do |key, value|
            if pick < value
              watcher_name  = key
              break
            else
              pick -= value
            end
          end
        end

        if watcher_name.nil?
          log.warn "synapse: s3 toggle resolver: failed to pick a watcher"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.switch', ['result:fail', 'reason:no_choice'])
        else
          log.info "synapse: s3 toggle resolver: chose watcher #{watcher_name}"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.switch', ['result:success', "watcher:#{watcher_name}"])
        end

        return watcher_name
      end

      def read_s3_file(bucket, key)
        data =
          begin
            resp = @@s3_client.get_object(bucket_name: bucket, key: key)
            parsed = YAML.load(resp.data[:data])

            log.info "synapse: s3 toggle resolver: read s3 file: #{parsed}"
            parsed
          rescue Psych::SyntaxError, TypeError => e
            log.warn "synapse: s3 toggle resolver: failed to parse s3 file: #{e}"
            statsd_increment('synapse.watcher.multi.resolver.s3_toggle.fetch_failure', ["reason:parse_error"])
            nil
          rescue AWS::Errors::Base => e
            log.warn "synapse: s3 toggle resolver: failed to fetch s3 file: #{e}"
            statsd_increment('synapse.watcher.multi.resolver.s3_toggle.fetch_failure', ["reason:s3_error"])
            nil
          end

        if validate_s3_file_schema(data)
          return data
        else
          log.warn "synapse: s3 toggle resolver: s3 file has invalid schema"
          statsd_increment('synapse.watcher.multi.resolver.s3_toggle.fetch_failure', ["reason:invalid_schema"])

          return nil
        end
      end

      # expected schema is {'watcher_name' => Integer, ...}
      def validate_s3_file_schema(contents)
        return false if (
            contents.nil? ||
            !contents.is_a?(Hash)
          )

        contents.each do |key, value|
          return false unless key.is_a?(String) && value.is_a?(Integer) && value >= 0
        end

        return true
      end
    end
  end
end
