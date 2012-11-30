
module Synapse
  class ZookeeperWatcher < ServiceWatcher

    def initialize(opts={}, synapse)
      super

      raise ArgumentError, "invalid discovery method '#{@discovery['method']}' for stub watcher" \
        unless @discovery['method'] == 'stub' 

      log "WARNING: a stub watcher with no default servers is pretty useless" if @default_servers.empty?
    end

    def start
      log "Starting stub watcher -- this means doing nothing at all!"
    end
  end
end
