require_relative "./base"

require 'zk'

module Synapse
  class ZookeeperWatcher < BaseWatcher
    def start
      zk_hosts = @discovery['hosts'].shuffle.join(',')

      log.info "synapse: starting ZK watcher #{@name} @ hosts: #{zk_hosts}, path: #{@discovery['path']}"
      @zk = ZK.new(zk_hosts)

      # call the callback to bootstrap the process
      watcher_callback.call
    end

    def ping?
      @zk.ping?
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'zookeeper'
      raise ArgumentError, "missing or invalid zookeeper host for service #{@name}" \
        unless @discovery['hosts']
      raise ArgumentError, "invalid zookeeper path for service #{@name}" \
        unless @discovery['path']
    end

    # helper method that ensures that the discovery path exists
    def create(path)
      log.debug "synapse: creating ZK path: #{path}"
      # recurse if the parent node does not exist
      create File.dirname(path) unless @zk.exists? File.dirname(path)
      @zk.create(path, ignore: :node_exists)
    end

    # find the current backends at the discovery path; sets @backends
    def discover
      log.info "synapse: discovering backends for service #{@name}"

      new_backends = []
      begin
        @zk.children(@discovery['path'], :watch => true).map do |name|
          node = @zk.get("#{@discovery['path']}/#{name}")

          begin
            host, port = deserialize_service_instance(node.first)
          rescue
            log.error "synapse: invalid data in ZK node #{name} at #{@discovery['path']}"
          else
            server_port = @server_port_override ? @server_port_override : port

            log.debug "synapse: discovered backend #{name} at #{host}:#{server_port} for service #{@name}"
            new_backends << { 'name' => name, 'host' => host, 'port' => server_port, 'backup' => @leader_election }
          end
        end
      rescue ZK::Exceptions::NoNode
        # the path must exist, otherwise watch callbacks will not work
        create(@discovery['path'])
        retry
      end

      if new_backends.empty?
        if @default_servers.empty?
          log.warn "synapse: no backends and no default servers for service #{@name}; using previous backends: #{@backends.inspect}"
        else
          log.warn "synapse: no backends for service #{@name}; using default servers: #{@default_servers.inspect}"
          @backends = @default_servers
        end
      else
        log.info "synapse: discovered #{new_backends.length} backends for service #{@name}"
        @backends = new_backends

        if @leader_election
          log.info "synapse: electing a leader from the discovered backends"
          begin
            #sort the list of servers based on their sequence, and the server with lowest 
            #sequence will be the leader
            #Integer parsing added to check that a sequence has been appended to the node key
            @backends = @backends.sort { |x, y| Integer(x['name'].gsub(/^.*-(0)*/, '')) <=> Integer(y['name'].gsub(/^.*-(0)*/, '')) }
            @backends[0]['backup'] = false
            log.debug "synapse: electing leader, updated backends #{@backends}"
          rescue ArgumentError, NoMethodError
            raise "'sequential' should be enabled in nerve configuration for service " \
              "#{@name} to perform leader election, please enable 'sequential' in nerve" \
              " configuration for all servers of #{@name} service,  or disable " \
              "'leader_election' in synapse configuration"
          end
        end
      end
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch
      @watcher.unsubscribe if defined? @watcher
      @watcher = @zk.register(@discovery['path'], &watcher_callback)
    end

    # handles the event that a watched path has changed in zookeeper
    def watcher_callback
      @callback ||= Proc.new do |event|
        # Set new watcher
        watch
        # Rediscover
        discover
        # send a message to calling class to reconfigure
        @synapse.reconfigure!
      end
    end

    # tries to extract host/port from a json hash
    def parse_json(data)
      begin
        json = JSON.parse data
      rescue Object => o
        return false
      end
      raise 'instance json data does not have host key' unless json.has_key?('host')
      raise 'instance json data does not have port key' unless json.has_key?('port')
      return json['host'], json['port']
    end

    # decode the data at a zookeeper endpoint
    def deserialize_service_instance(data)
      log.debug "synapse: deserializing process data"

      # if that does not work, try json
      host, port = parse_json(data)
      return host, port if host

      # if we got this far, then we have a problem
      raise "could not decode this data:\n#{data}"
    end
  end
end
