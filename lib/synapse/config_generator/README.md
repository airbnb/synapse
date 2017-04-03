## ConfigGenerator Classes

Generators are the piece of Synapse that react to changes in service
registrations and actually reflect those changes in local state.
Generators should conform to the interface specified by `BaseGenerator` and
when your generator has received an update from synapse via `update_config` it
should sync the watcher state with the external configuration (e.g. HAProxy
state)

Note that you have access to the following **read only** methods on the
watchers:

* `config_for_generator[name]` -> Hash: A method for retrieving the watcher config
 relevant to this particular config watcher.
* `revision` -> int: A logical, monotonically increasing clock indicating which
  revision of the watcher this is. You can use this to ignore config updates
  from watchers that haven't changed

```ruby
require "synapse/config_generator/base"

class Synapse::ConfigGenerator
  class MyGenerator < BaseGenerator
    # The generator name is used to find service specific
    # configuration in the service watchers. When supplying
    # per service config, use this as the key
    NAME = 'my_generator'.freeze

    def initialize(opts = {})
        # Process and validate any options specified in the dedicated section
        # for this config generator, given as the `opts` hash. You may omit
        # this method, or you can declare your own, but remember to invoke
        # the parent initializer
        super(opts)
    end

    def update_config(watchers)
      # synapse will call this method whenever watcher state changes with the
      # watcher state. You should reflect that state in the local config state
    end

    def tick
      # Called every loop of the main Synapse loop regardless of watcher
      # changes (roughly ~1s). You can use this to rate limit how often your
      # config generator actually reconfigures external services (e.g. HAProxy
      # may need to rate limit reloads as those can be disruptive to in
      # flight connections
    end

    def normalize_watcher_provided_config(service_watcher_name, service_watcher_config)
      # Every service watcher section of the Synapse configuration can contain
      # options that change how the config generators react for that
      # particular service. This normalize method is a good place to ensure
      # you set options your generator expects every service watcher config
      # to supply, providing, for example, default values. This is also a
      # good place to raise errors in case any options are invalid.
    end
  end
end
```

### Generator Plugin Inteface
Synapse deduces both the class path and class name from any additional keys
passed to the top level configuration, which it assumes are equal to the `NAME`
of some ConfigGenerator. For example, if `haproxy` is set at the top level we
try to load the `Haproxy` `ConfigGenerator`.

#### Class Location
Synapse expects to find your class at `synapse/config_generator/#{name}`. You
must make your generator available at that path, and Synapse can "just work" and
find it.

#### Class Name
These type strings are then transformed into class names via the following
function:

```
type_class  = type.split('_').map{|x| x.capitalize}
```

This has the effect of taking the method, splitting on `_`, capitalizing each
part and recombining. So `file_output` becomes `FileOutput` and `haproxy`
becomes `Haproxy`. Make sure your class name is correct.
