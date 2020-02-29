require "synapse/log"
require "synapse/service_watcher/base"
require "synapse/service_watcher/multi"

module Synapse
  class ServiceWatcher
    # the method which actually dispatches watcher creation requests
    def self.create(name, opts, synapse, reconfigure_callback)
      opts = self.resolve_multi_config(opts)
      opts['name'] = name

      raise ArgumentError, "Missing discovery method when trying to create watcher" \
        unless opts.has_key?('discovery') && opts['discovery'].has_key?('method')

      discovery_method = opts['discovery']['method']
      return self.load_watcher(discovery_method, opts, synapse, reconfigure_callback)
    end

    def self.load_watcher(discovery_method, opts, synapse, reconfigure_callback)
      watcher = begin
        method = discovery_method.downcase
        require "synapse/service_watcher/#{method}"
        # zookeeper_dns => ZookeeperDnsWatcher, ec2tag => Ec2tagWatcher, etc ...
        method_class  = method.split('_').map{|x| x.capitalize}.join.concat('Watcher')
        self.const_get("#{method_class}")
      rescue Exception => e
        raise ArgumentError, "Specified a discovery method of #{discovery_method}, which could not be found: #{e}"
      end

      return watcher.new(opts, synapse, reconfigure_callback)
    end

    private
    def self.resolve_multi_config(opts)
      if opts.has_key?('discovery_multi')
        multi = opts.delete('discovery_multi')
        opts['discovery'] = MultiWatcher.merge_discovery(multi, opts['discovery'])
      end

      return opts
    end
  end
end
