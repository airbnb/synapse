require 'synapse/service_watcher/base'
require 'marathon'

module Synapse
  class MarathonWatcher < BaseWatcher

    attr_reader :check_interval
    attr_reader :port_index

    def start
      @marathon = Marathon::Client.new(
        @discovery['hostname'],
        @discovery['username'],
        @discovery['password']
      )

      @check_interval = @discovery['check_interval'] || 15.0

      @watcher = Thread.new do
        watch
      end
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'marathon'
      raise ArgumentError, "non-empty hostname is required for service #{@name}" \
        if @discovery['hostname'].nil? or @discovery['hostname'].empty?
      raise ArgumentError, "non-empty app_id is required for service #{@name}" \
        if @discovery['app_id'].nil? or @discovery['app_id'].empty?
      raise ArgumentError, "Invalid port_index value" \
        if not @discovery['port_index'].nil? and not @discovery['port_index'].empty? and not @discovery['port_index'].match(/^\d+$/)

      @port_index = @discovery['port_index'].to_i || 0
    end

    def watch
      last_backends = []
      until @should_exit
        begin
          start = Time.now
          current_backends = discover_instances

          if last_backends != current_backends
            log.info "synapse: marathon watcher backends have changed."
            last_backends = current_backends
            configure_backends(current_backends)
          else
            log.info "synapse: marathon watcher backends are unchanged."
          end

          sleep_until_next_check(start)
        rescue Exception => e
          log.warn "synapse: error in marathon watcher thread: #{e.inspect}"
          log.warn e.backtrace
        end
      end

      log.info "synapse: marathon watcher exited successfully"
    end

    def sleep_until_next_check(start_time)
      sleep_time = @check_interval - (Time.now - start_time)
      if sleep_time > 0.0
        sleep(sleep_time)
      end
    end

    def discover_instances
        tasks = list_app_tasks(@discovery['app_id'])

        new_backends = []

        tasks.each do |task|
          new_backends << {
            'name' => task.id,
            'host' => task.host,
            'port' => task.ports[@port_index]
          }
        end

        new_backends
    end

    def list_app_tasks(app_id)
      @marathon.list_tasks(app_id).parsed_response['tasks']
    end

    def configure_backends(new_backends)
      if new_backends.empty?
        if @default_servers.empty?
          log.warn "synapse: no backends and no default servers for service #{@name};" \
            " using previous backends: #{@backends.inspect}"
        else
          log.warn "synapse: no backends for service #{@name};" \
            " using default servers: #{@default_servers.inspect}"
          @backends = @default_servers
        end
      else
        log.info "synapse: discovered #{new_backends.length} backends for service #{@name}"
        set_backends(new_backends)
      end
      reconfigure!
    end

  end

end

