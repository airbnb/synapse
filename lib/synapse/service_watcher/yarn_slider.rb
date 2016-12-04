require 'synapse/service_watcher/base'
require 'json'
require 'net/http'
require 'resolv'

class Synapse::ServiceWatcher
  class YarnSliderWatcher < BaseWatcher
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
      required_opts = %w[yarn_api_url application_name]

      required_opts.each do |opt|
        if @discovery.fetch(opt, '').empty?
          raise ArgumentError,
            "a value for services.#{@name}.discovery.#{opt} must be specified"
        end
      end
    end

    def attempt_connection(url)
      uri = URI(url)
      log.debug "synapse: try connect to #{uri}"
      begin
        connection = Net::HTTP.new(uri.host, uri.port)
        connection.open_timeout = 5
        connection.start
        return connection
      rescue => ex
        log.error "synapse: could not connect to YARN at #{url}: #{ex}"
        raise ex
      end
    end 

    def try_find_yarn_app_master_traking_url(name)
      begin
        yarn_rm_connection = attempt_connection(@discovery['yarn_api_url'])
        yarn_apps_path = @discovery.fetch('yarn_apps_path', '/ws/v1/cluster/apps?limit=2&state=RUNNING&applicationTypes=org-apache-slider&applicationTags=name:%20')
        yarn_path_resolved =  yarn_apps_path + name
        log.debug "synapse resolved yarn path #{yarn_path_resolved}"
        req = Net::HTTP::Get.new(yarn_path_resolved)
        req['Content-Type'] = 'application/json'
        req['Accept'] = 'application/json'
        response = yarn_rm_connection.request(req)
        log.debug "synapse yarn apps response\n#{response.body}"
        apps = JSON.parse(response.body).fetch('apps', [])
        if apps.nil?
          raise 'No yarn application with name ' + name
        end 
        if apps['app'].size > 1
          raise 'More then 1 yarn application with name ' + name
        end 
        return apps['app'].at(0)['trackingUrl']
      rescue => ex
        log.warn "synapse: error while watcher try find yarn application: #{ex.inspect}"
        log.warn ex.backtrace.join("\n")
        raise ex
      end
    end

    def watch
      until @should_exit
        retry_count = 0
        start = Time.now

        begin
          if @connection.nil?
            app_am_url = try_find_yarn_app_master_traking_url(@discovery['application_name'])
            log.debug "synapse: try connect to app traking url #{app_am_url}"
            @slider_component_instance_url = URI(app_am_url + @discovery.fetch('slider_componentinstance_path', '/ws/v1/slider/publisher/slider/componentinstancedata'))
            @connection = attempt_connection(@slider_component_instance_url)
          end

          req = Net::HTTP::Get.new(@slider_component_instance_url.request_uri)
          req['Content-Type'] = 'application/json'
          req['Accept'] = 'application/json'
          response = @connection.request(req)

          lookup_sufix = @discovery.fetch('parameter_sufix', '.server_port')
          entries = JSON.parse(response.body).fetch('entries', [])
          backends = entries.keep_if{ |entry| entry.include? lookup_sufix }.map do |key, value|
            { 'name' => key[/(.*)#{lookup_sufix}/,1],
              'host' => value[/(.*):.*/,1],
              'port' => value[/.*:(.*)/,1],
            }
          end.sort_by { |entry| entry['name'] }

          set_backends(backends)
        rescue EOFError
          # If the persistent HTTP connection is severed, we can automatically
          # retry
          log.info "synapse: yarn_slider HTTP API at {@slider_component_instance_url} disappeared, reconnecting..."
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