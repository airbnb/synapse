require "synapse/service_watcher/base/poll"
require 'docker'

class Synapse::ServiceWatcher
  class DockerWatcher < PollWatcher
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

    def discover
      set_backends(containers)
    end

    def rewrite_container_ports(ports)
      pairs = []
      if ports.is_a?(String)
        # "Ports" comes through (as of 0.6.5) as a string like "0.0.0.0:49153->6379/tcp, 0.0.0.0:49153->6379/tcp"
        # Convert string to a map of container port to host port: {"7000"->"49158", "6379": "49159"}
        pairs = ports.split(", ").collect do |v|
          pair = v.split('->')
          [ pair[1].rpartition("/").first, pair[0].rpartition(":").last ]
        end
      elsif ports.is_a?(Array)
        # New style API, ports is an array of hashes, with numeric values (or nil if no ports forwarded)
        pairs = ports.collect do |v|
          [v['PrivatePort'].to_s, v['PublicPort'].to_s]
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
        # Discover containers that match the image/port we're interested in and have the port mapped to the host
        cnts = cnts.find_all do |cnt|
          cnt["Image"].rpartition(":").first == @discovery["image_name"] \
            and cnt["Ports"].has_key?(@discovery["container_port"].to_s()) \
            and cnt["Ports"][@discovery["container_port"].to_s()].length > 0
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
      log.warn "synapse: error while polling for containers: #{e.inspect}"
      []
    end
  end
end
