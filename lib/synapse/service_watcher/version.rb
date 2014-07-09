require 'synapse/service_watcher/zookeeper'

require 'zk'

# To avoid the collision of different releases (as by default all nodes
# share the same path) in immutable infrastructure we need some sort of 
# identifier which tells about the active version so we can switch
# between different releases.

# This watcher is build on top of ZK watcher. It will watch the active version
# along with the nodes and as soon as a version changes it will update the 
# synapse config with latest version and reload the haproxy.
# e.g. version 1 nodes are resgitered in the following path using nerve
# `/services/service1/v1` and the active version path `/version/service1`
# is set to v1. All version 2 nodes will go to `/service/service1/v2` and
# once all the nodes are ready we can switch version to v2 on `/version/service1`
module Synapse
  class VersionWatcher < ZookeeperWatcher
    def start
      @zk_hosts = @discovery['hosts'].shuffle.join(',')
      
      @watcher = nil
      @zk = nil

      log.info "synapse: starting ZK watcher #{@name} @ hosts: #{@zk_hosts}, path: #{@discovery['path']}"
      zk_connect
      # make sure version path exists
      create(@discovery['version_path'])
      # starting active production version watcher
      version_watcher_callback.call
    end

    private

    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'version'

      %w{hosts path version_path synapse_config reload_command}.each do |required|
        raise ArgumentError, "missing required argument #{required} in VersionWatcher check" \
          unless  @discovery[required]
      end
    end

    # find the current version at the discovery path; update synapse config
    def discover_version
      version = @zk.get(@discovery['version_path'], :watch => true).first
      log.info "#{version}"
      if !version.nil? and !version.empty?
        synapse_config = @discovery['synapse_config']
        log.debug "synapse: discovered version #{version}"
        updated_path = @discovery['path'].split("/")
        # remove the old version
        old_version = updated_path.pop
        if old_version != version
          # append the new version
          updated_path = updated_path + ["#{version}"]
          updated_path = updated_path.join("/")
          log.info("updated path #{updated_path}")
          if @discovery['path'] != updated_path
            @restart_synapse = true
            File.open( synapse_config, "r" ) do |f|
              @config_data = JSON.load( f )
              log.info("updating path #{updated_path} for service #{name}")
              @config_data['services'][name]['discovery']['path'] = updated_path
            end
            File.open( synapse_config, "w" ) do |fw|
              fw.write(JSON.pretty_generate(@config_data))
            end
          end
        end
      end
    end

    # sets up zookeeper callbacks if the data at the discovery path changes
    def watch_version
      @version_watcher.unsubscribe if defined? @version_watcher
      @version_watcher = @zk.register(@discovery['version_path'], &version_watcher_callback)
    end

    # handles the event that a watched path has changed in zookeeper
    def version_watcher_callback
      @version_callback ||= Proc.new do |event|
        # Set new watcher
        watch_version
        # Rediscover
        discover_version
        # restart synapse
        if @restart_synapse
          @restart_synapse = false
          log.info("restarting synapse")
          res = `#{@discovery['reload_command']}`
          log.debug(res)
          raise "failed to reload haproxy via #{@discovery['reload_command']}: #{res}" unless $?.success?
        end
      end
    end

  end
end
