require 'synapse/log'

class Synapse::ConfigGenerator
  class BaseGenerator
    include Synapse::Logging
    attr_reader :name, :opts

    # The synapse main loop will call this every tick
    # of the logical clock (~1s). You can use this to intiate reloads
    # or restarts in a rate limited fashion
    def tick
    end

    # The synapse main loop will call this any time watchers change, the
    # config_generator is responsible for diffing the passed watcher state
    # against the output configuration
    def update_config(watchers)
    end

    # Service watchers have a subsection of their ``services`` entry that is
    # dedicated to the watcher specific configuration for how to configure
    # the config generator. This method will be called with each of these
    # watcher hashes, and should normalize them to what the config generator
    # needs, such as adding defaults. Mutate the passed hash
    def normalize_config_generator_opts!(service_watcher_name, service_watcher_opts)
    end

  end
end
