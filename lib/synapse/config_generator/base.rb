require 'synapse/log'

class Synapse::ConfigGenerator
  class BaseGenerator
    include Synapse::Logging
    attr_reader :name, :opts

    # The synapse main loop will call this every tick
    # of the logical clock (~1s)
    def tick
    end

    # The synapse main loop will call this any time
    # watchers change
    def update_config(watchers)
    end

  end
end
