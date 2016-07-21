require 'synapse/log'
require 'synapse/config_generator/base'

module Synapse
  class ConfigGenerator
    # the type which actually dispatches generator creation requests
    def self.create(type, opts)
      generator = begin
        type = type.downcase
        require "synapse/config_generator/#{type}"
        # haproxy => Haproxy, file_output => FileOutput, etc ...
        type_class  = type.split('_').map{|x| x.capitalize}.join
        self.const_get("#{type_class}")
      rescue Exception => e
        raise ArgumentError, "Specified a config generator of #{type}, which could not be found: #{e}"
      end
      return generator.new(opts)
    end
  end
end
