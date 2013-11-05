require_relative "./base"
require 'docker'

module Synapse
  class DockerWatcher < BaseWatcher
    def start
      @check_interval = @discovery['check_interval'] || 15.0
      watch
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'docker'
      raise ArgumentError, "a non-empty list of servers is required" \
        if @discovery['servers'].empty?
      raise ArgumentError, "non-empty image_name required" \
        if @discovery['image_name'].nil? or @discovery['image_name'].empty?
      raise ArgumentError, "container_port required" \
        if @discovery['container_port'].nil?
    end

    def watch
      @watcher = Thread.new do
        last_containers = containers
        configure_backends(last_containers)
        while true
          begin
            start = Time.now
            current_containers = containers
            unless last_containers == current_containers
              last_containers = current_containers
              configure_backends(last_containers)
            end

            sleep_until_next_check(start)
          rescue => e
            log.warn "Error in watcher thread: #{e.inspect}"
            log.warn e.backtrace
          end
        end
      end
    end

    def sleep_until_next_check(start_time)
      sleep_time = @check_interval - (Time.now - start_time)
      if sleep_time > 0.0
        sleep(sleep_time)
      end
    end

    def containers
      backends = @discovery['servers'].map do |server|
        Docker.url = "http://#{server['host']}:#{server['port']}"
        cnts = Docker::Util.parse_json(Docker.connection.get('/containers/json', {}))
        # "Ports" comes through as a string like "49158->7000, 49159->6379"
        # Convert string to a map of container port to host port: {"7000"->"49158", "6379": "49159"}
        cnts.each do |cnt|
          cnt["Ports"] = Hash[cnt["Ports"].split(", ").collect { |v| v.split('->').reverse }]
        end
        # Discover containers that match the image/port we're interested in
        cnts = cnts.find_all do |cnt|
          cnt["Image"].rpartition(":").first == @discovery["image_name"] \
            and cnt["Ports"].has_key?(@discovery["container_port"].to_s())
        end
        cnts.map do |cnt|
          {
            'name' => server['name'],
            'host' => server['host'],
            'port' => cnt["Ports"][@discovery["container_port"].to_s()]
          }
        end
      end
      backends.flatten
    rescue => e
      log.warn "Error while polling for containers: #{e.inspect}"
      []
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
        @backends = new_backends
      end
      @synapse.reconfigure!
    end

  end
end
