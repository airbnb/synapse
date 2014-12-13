require "synapse/service_watcher/base"
require 'json'
require 'resolv'

module Synapse
  class MarathonWatcher < BaseWatcher
    def start
      @check_interval = @discovery['check_interval'] || 10.0

      @marathon_api = URI.join(@discovery['marathon_api_url'], "/v2/apps/#{@discovery['application_name']}/tasks")
      @connection = Net::HTTP.new(@marathon_api.host, @marathon_api.port)
      @connection.open_timeout = 5
      @connection.start

      @watcher = Thread.new { watch }
    end

    def stop
      @connection.finish
    rescue
      # pass
    end

  private

    def validate_discovery_opts
      required_opts = %w[marathon_api_url application_name]

      required_opts.each do |opt|
        if @discovery.fetch(opt, '').empty?
          raise ArgumentError,
            "a value for services.#{@name}.discovery.#{opt} must be specified"
        end
      end
    end

    def watch
      until @should_exit
        retry_count = 0
        start = Time.now

        begin
          req = Net::HTTP::Get.new(@marathon_api.request_uri)
          req['Accept'] = 'application/json'
          response = @connection.request(req)

          tasks = JSON.parse(response.body).fetch('tasks', [])
          backends = tasks.keep_if { |task| task['startedAt'] }.map do |task|
            {
              'name' => task['host'],
              'host' => task['host'],
              'port' => task['ports'].first,
            }
          end.sort_by { |task| task['name'] }

          if backends.empty?
            log.warn "synapse: no backends discovered for #{@discovery['application_name']}"
          else
            previous_backends = @backends
            set_backends(backends)
            new_backends = @backends

            unless previous_backends == new_backends
              log.info "synapse: found #{backends.length} backends for #{@discovery['application_name']}"

              reconfigure!
            end
          end
        rescue EOFError
          # If the persistent HTTP connection is severed, we can automatically
          # retry
          log.info "synapse: marathon HTTP API disappeared, reconnecting..."

          retry if (retry_count += 1) == 1
        rescue Exception => e
          log.warn "synapse: error in watcher thread: #{e.inspect}"
          log.warn e.backtrace.join("\n")
        ensure
          elapsed_time = Time.now - start
          sleep (@check_interval - elapsed_time) if elapsed_time < @check_interval
        end

        @should_exit = true if only_run_once? # for testability
      end
    end

    def only_run_once?
      false
    end
  end
end
