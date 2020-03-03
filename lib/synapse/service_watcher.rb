require "synapse/log"
require "synapse/service_watcher/base"

module Synapse
  class ServiceWatcher
    # the method which actually dispatches watcher creation requests
    def self.create(name, opts, reconfigure_callback = nil, synapse)
      opts['name'] = name

      raise ArgumentError, "Missing discovery method when trying to create watcher" \
        unless opts.has_key?('discovery') && opts['discovery'].has_key?('method')

      discovery_method = opts['discovery']['method']
      return self.load_watcher(discovery_method, opts, reconfigure_callback, synapse)
    end

    def self.load_watcher(discovery_method, opts, reconfigure_callback = nil, synapse)
      watcher = begin
        method = discovery_method.downcase
        require "synapse/service_watcher/#{method}"
        # zookeeper_dns => ZookeeperDnsWatcher, ec2tag => Ec2tagWatcher, etc ...
        method_class  = method.split('_').map{|x| x.capitalize}.join.concat('Watcher')
        self.const_get("#{method_class}")
      rescue Exception => e
        raise ArgumentError, "Specified a discovery method of #{discovery_method}, which could not be found: #{e}"
      end

      return watcher.new(opts, reconfigure_callback, synapse)
    end
  end
end
