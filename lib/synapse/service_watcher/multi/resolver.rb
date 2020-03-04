class Synapse::ServiceWatcher
  class Resolver
    def self.load_resolver(opts, watchers)
      raise ArgumentError, "resolver method not provided" unless opts.has_key?('method')
      method = opts['method'].downcase

      resolver = begin
                   require "synapse/service_watcher/multi/resolver/#{method}"
                   method_class  = method.split('_').map{|x| x.capitalize}.join.concat('Resolver')
                   self.const_get("#{method_class}")
                 rescue Exception => e
                   raise ArgumentError, "specified a resolver method of #{method}, which could not be found: #{e}"
                 end

      return resolver.new(opts, watchers)
    end
  end
end
