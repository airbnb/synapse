require 'synapse/service_watcher/base/base'
require 'json'
require 'net/http'
require 'resolv'

class Synapse::ServiceWatcher
  class MarathonWatcher < BaseWatcher
    def start
      @check_interval = @discovery['check_interval'] || 10.0
      @connection = nil
      @watcher = Thread.new { sleep splay; watch }
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

    def attempt_marathon_connection
      marathon_api_path = @discovery.fetch('marathon_api_path', '/v2/apps/%{app}/tasks')
      marathon_api_path = marathon_api_path % { app: @discovery['application_name'] }

      @marathon_api = URI.join(@discovery['marathon_api_url'], marathon_api_path)

      begin
        @connection = Net::HTTP.new(@marathon_api.host, @marathon_api.port)
        @connection.open_timeout = 5
        @connection.start
      rescue => ex
        @connection = nil
        log.error "synapse: could not connect to marathon at #{@marathon_api}: #{ex}"

        raise ex
      end
    end

    def watch
      until @should_exit
        retry_count = 0
        start = Time.now

        begin
          if @connection.nil?
            attempt_marathon_connection
          end

          req = Net::HTTP::Get.new(@marathon_api.request_uri)
          req['Accept'] = 'application/json'
          response = @connection.request(req)

          tasks = JSON.parse(response.body).fetch('tasks', [])
          port_index = @discovery['port_index'] || 0
          backends = tasks.keep_if { |task| task['startedAt'] }.map do |task|
            {
              'name' => task['host'],
              'host' => task['host'],
              'port' => task['ports'][port_index],
            }
          end.sort_by { |task| task['name'] }

          invalid_backends = backends.find_all { |b| b['port'].nil? }
          if invalid_backends.any?
            backends = backends - invalid_backends

            invalid_backends.each do |backend|
              log.error "synapse: port index #{port_index} not found in task's port array!"
            end
          end

          set_backends(backends)
        rescue EOFError
          # If the persistent HTTP connection is severed, we can automatically
          # retry
          log.info "synapse: marathon HTTP API disappeared, reconnecting..."

          retry if (retry_count += 1) == 1
        rescue => e
          log.warn "synapse: error in watcher thread: #{e.inspect}"
          log.warn e.backtrace.join("\n")
          @connection = nil
        ensure
          elapsed_time = Time.now - start
          sleep (@check_interval - elapsed_time) if elapsed_time < @check_interval
        end

        @should_exit = true if only_run_once? # for testability
      end
    end

    def splay
      Random.rand(@check_interval)
    end

    def only_run_once?
      false
    end
  end
end
