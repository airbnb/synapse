require 'synapse/log'

class Synapse::ConfigGenerator
  class BaseGenerator
    include Synapse::Logging

    NAME = 'base'.freeze

    attr_reader :opts

    def initialize(opts={})
      @opts = opts
    end

    # Exposes NAME as 'name' so we can remain consistent with how we refer to
    # service_watchers' by generator.name access (instead of
    # generator.class::NAME) even though the names of generators don't change
    def name
      self.class::NAME
    end

    # The synapse main loop will call this any time watchers change, the
    # config_generator is responsible for diffing the passed watcher state
    # against the output configuration
    def update_config(watchers)
    end

    # The synapse main loop will call this every tick
    # of the logical clock (~1s). You can use this to intiate reloads
    # or restarts in a rate limited fashion
    def tick
    end

    # Service watchers have a subsection of their ``services`` entry that is
    # dedicated to the watcher specific configuration for how to configure
    # the config generator. This method will be called with each of these
    # watcher hashes, and should normalize them to what the config generator
    # needs, such as adding defaults. Return the properly populated default hash
    def normalize_watcher_provided_config(service_watcher_name, service_watcher_config)
      service_watcher_config.dup
    end

  end
end
