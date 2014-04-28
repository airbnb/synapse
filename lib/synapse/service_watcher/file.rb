require "synapse/service_watcher/base"

require 'listen'

module Synapse
  class FileWatcher < BaseWatcher
    def start
      log.info "synapse: starting file watcher #{@name} @ path: #{server_list_path}"
      reload_backends
      @listener = create_listener
      @listener.start
    end

    def stop
      log.warn "synapse: file watcher exiting"
      @listener.stop
      log.info "synapse: file watcher stopped successfully"
    end

    def ping?
      @listener.listen?
    end

    private
    def server_list_path
      @discovery['path']
    end

    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'file'
      raise ArgumentError, "missing or invalid path for service #{@name}" \
        unless server_list_path
      raise ArgumentError, "server list file for service #{@name} doesn't exist or is not a file" \
        unless File.file?(server_list_path)
    end

    def create_listener
      dir = File.dirname(server_list_path)
      basename = File.basename(server_list_path)
      Listen.to(dir, only: /\A#{Regexp.escape(basename)}\z/) do |modified, added, removed|
        reload_backends
      end
    end

    def reload_backends
      new_backends = []

      open(server_list_path) do |f|
        f.each_line do |line|
          host, port = line.split(' ')
          if host && port
            new_backends << {'host' => host, 'port' => port}
          end
        end
      end

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
