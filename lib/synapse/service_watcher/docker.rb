require "synapse/service_watcher/base"
require 'docker'

module Synapse
  class DockerWatcher < BaseWatcher
    def start
      @check_interval = @discovery['check_interval'] || 15.0
      @watcher = Thread.new do
        watch
      end
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'docker'
      raise ArgumentError, "a non-empty list of servers is required" \
        if @discovery['servers'].nil? or @discovery['servers'].empty?
      raise ArgumentError, "non-empty image_name required" \
        if @discovery['image_name'].nil? or @discovery['image_name'].empty?
      raise ArgumentError, "container_port required" \
        if @discovery['container_port'].nil?
    end

    def watch
      last_containers = []
      until @should_exit
        begin
          start = Time.now
          current_containers = containers
          unless last_containers == current_containers
            last_containers = current_containers
            configure_backends(last_containers)
          end

          sleep_until_next_check(start)
        rescue Exception => e
          log.warn "synapse: error in watcher thread: #{e.inspect}"
          log.warn e.backtrace
        end
      end

      log.info "synapse: docker watcher exited successfully"
    end

    def sleep_until_next_check(start_time)
      sleep_time = @check_interval - (Time.now - start_time)
      if sleep_time > 0.0
        sleep(sleep_time)
      end
    end

    def rewrite_container_ports(ports)
      pairs = []
      if ports.is_a?(String)
        # "Ports" comes through (as of 0.6.5) as a string like "0.0.0.0:49153->6379/tcp, 0.0.0.0:49153->6379/tcp"
        # Convert string to a map of container ports and host to host port:
        # {"7000"-> { "host": "localhost", "port": 49158" }, etc..}
        pairs = ports.split(", ").collect do |v|
          pair = v.split("->")
          [
            pair[1].rpartition("/").first,
            {
              "host" => vpair[0].rpartition(":").first,
              "port" => vpair[0].rpartition(":").last
            }
          ]
        end
      elsif ports.is_a?(Array)
        # New style API, ports is an array of hashes, with numeric values (or nil if no ports forwarded)
        pairs = ports.collect do |v|
          [ v["PrivatePort"].to_s, { "host" => v["IP"], "port" => v["PublicPort"].to_s } ]
        end
      end
      Hash[pairs]
    end

    def containers
      backends = @discovery['servers'].map do |server|
        Docker.url = "http://#{server['host']}:#{server['port'] || 4243}"
        begin
          cnts = Docker::Util.parse_json(Docker.connection.get('/containers/json', {}))
        rescue => e
          log.warn "synapse: error polling docker host #{Docker.url}: #{e.inspect}"
          next []
        end
        cnts.each do |cnt|
          cnt['Ports'] = rewrite_container_ports cnt['Ports']
        end
        # Discover containers that match the image/port we're interested in
        cnts = cnts.find_all do |cnt|
          cnt["Image"].rpartition(":").first == @discovery["image_name"] \
            and cnt["Ports"].has_key?(@discovery["container_port"].to_s())
        end
        cnts.map do |cnt|
          {
            'name' => server['name'],
            'host' => if cnt["Ports"][@discovery["container_port"].to_s()]["host"] == "0.0.0.0" \
                          or cnt["Ports"][@discovery["container_port"].to_s()]["host"] == ""
                        server["host"]
                      else
                        cnt["Ports"][@discovery["container_port"].to_s()]["host"]
                      end,
            'port' => cnt["Ports"][@discovery["container_port"].to_s()]["port"]
          }
        end
      end
      backends.flatten
    rescue => e
      log.warn "synapse: error while polling for containers: #{e.inspect}"
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
        set_backends(new_backends)
      end
      reconfigure!
    end

  end
end
