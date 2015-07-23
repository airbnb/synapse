require "synapse/service_watcher/base"
require "zk"
require "thread"

module Synapse
  class ZookeeperRecursiveWatcher < BaseWatcher

    # Overriden methods start, stop, validate_discovery_opts, ping
    def start
      boot unless @already_started
    end

    def boot
      @already_started = true
      log.info "#{@name}: Starting @ hosts: #{@discovery["hosts"]}, path: #{@discovery["path"]}, id #{self.object_id}"
      setup_zk_connection
      setup_haproxy_configuration
      start_watching_services
    end

    def stop
      log.info "#{@name}: Stopping using default stop handler"
      @subwatcher.each { |watcher| cleanup_service_watcher(watcher) }
      @should_exit = true
    end

    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery["method"]}" \
        unless @discovery["method"] == "zookeeper_recursive"
      raise ArgumentError, "missing or invalid zookeeper host for service #{@name}" \
        unless @discovery["hosts"]
      raise ArgumentError, "invalid zookeeper path for service #{@name}" \
        unless @discovery["path"]
    end

    def ping?
      @zk && @zk.connected?
    end

    # Methods for Initializing
    def setup_zk_connection
      @zk_hosts = @discovery["hosts"].shuffle.join(",")
      @zk = ZK.new(@zk_hosts)
    end

    def setup_haproxy_configuration
      @haproxy_template = @haproxy.dup
      #Purge the own haproxy-conf to a minimum, in order to be no haproxy-instance
      @haproxy = {"listen" => @haproxy["listen"]}
    end

    def start_watching_services
      @subwatcher = []
      create_if_not_exists(@discovery["path"])
      watch_services(@discovery["path"])
    end

    def create_if_not_exists(path)
      log.debug "#{@name}: Creating ZK path: #{path}"
      current = ""
      path.split("/").drop(1).each { |node|
        current += "/#{node}"
        @zk.create(current) unless @zk.exists?(current)
      }
    end

    # Methods for running
    def watch_services(path)
      log.info("Watching path #{path}")
      # Register each time a event is fired, since we"re getting only one event per register
      @zk.register(path, [:deleted, :child]) do |event|
        if event.node_deleted?
          cleanup_service_watcher(path)
        else
          watch_services(path)
        end
      end

      children = @zk.children(path, :watch => true).map { |child| "#{path}/#{child}" }

      persistent_children = children.select { |child| @zk.get("#{child}")[1].ephemeralOwner == 0 }
      persistent_children.each { |child| watch_services(child) }


      unless (path == @discovery["path"])
        if (!@subwatcher.include?(path) && persistent_children.empty?) then
          create_service_watcher(path)
        end
        if (@subwatcher.include?(path) && !persistent_children.empty?) then
          cleanup_service_watcher(path)
        end
      end
    end

    def create_service_watcher(service_path)
      service_name = service_path.gsub(/[\/\.]/, "_")
      service_config = {
          "discovery" => {
              "method" => "zookeeper",
              "path" => "#{service_path}",
              "hosts" => @discovery["hosts"],
              "empty_backend_pool" => @discovery["empty_backend_pool"]
          },
          "haproxy" => build_haproxy_section(service_name, service_path, @haproxy_template)
      }
      log.info "#{@name}: Creating new Service-Watcher for #{service_name}@ hosts: #{@zk_hosts}"
      log.debug service_config
      @subwatcher << service_path
      @synapse.append_service_watcher(service_name, service_config)
    end

    def build_haproxy_section(service_name, service_path, template)
      new_haproxy = {}
      template.each { |key, section| new_haproxy[key] = parse_section(section, service_name, service_path) }
      return new_haproxy
    end

    def parse_section(section, service_name, service_path)
      service_url = service_path.sub(@discovery["path"], "")
      service_url = "/" if service_url.empty?
      if section.is_a?(String)
        new_section = section.gsub(/#\[servicePath\]/, "#{service_url}").gsub(/#\[service\]/, "#{service_name}")
      else
        unless section.nil? || section == 0
          new_section = section.map { |subsection| parse_section(subsection, service_name, service_path) }
        end
      end
      new_section
    end

    def cleanup_service_watcher(service_path)
      service_name = service_path.gsub(/\//, "_")
      log.info("#{@name}: Removing Watcher: #{service_name}")
      @synapse.remove_watcher_by_name(service_name)
      @subwatcher.delete(service_path)
    end
  end
end
