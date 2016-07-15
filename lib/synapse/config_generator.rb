require 'synapse/log'
require 'synapse/config_generator/base'

module Synapse
  class ConfigGenerator
    # the method which actually dispatches generator creation requests
    def self.create(type, opts)
      generator = begin
        method = type.downcase
        require "synapse/config_generator/#{method}"
        # haproxy => Haproxy, file_output => FileOutput, etc ...
        method_class  = method.split('_').map{|x| x.capitalize}.join
        self.const_get("#{method_class}")
      rescue Exception => e
        raise ArgumentError, "Specified a config generator of #{method}, which could not be found: #{e}"
      end
      return generator.new(opts)
    end
  end
end
