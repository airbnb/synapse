## ConfigGenerator Classes

Generators are the piece of Synapse that react to changes in service
registrations and actually reflect those changes in local state.
Generators should conform to the interface specified by `BaseGenerator` and
when your generator has received an update from synapse via `update_config` it
should sync the watcher state with the external configuration (e.g. HAProxy
state)

```ruby
require "synapse/config_generator/base"

class Synapse::ServiceGenerator
  class MyGenerator < BaseGenerator
    # The generator name is used to find service specific
    # configuration in the service watchers. When supplying
    # per service config, use this as the key
    NAME = 'my_generator'.freeze

    def update_config(watchers)
      # synapse will call this method whenever watcher state changes with the
      # watcher state. You should reflect that state in the local config state
    end

    def tick
      # Called every loop of the main Synapse loop regardless of watcher #
      # changes (roughly ~1s), you can use this to rate limit how often your
      # config generator actually reconfigures external services (e.g. HAProxy
      # may need to rate limit reloads as those can be disruptive to in
      # flight connections
    end

    def normalize_config_generator_opts!(service_watcher_name, service_watcher_opts)
      # Every service section can contain configuration that changes how the
      # config generator reacts for that particular service. Typically this
      # is a good place to ensure you set config your generator expects every
      # service to supply in case they don't supply it
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

This has the effect of taking the method, splitting on '_', capitalizing each
part and recombining. So `file_output` becomes `FileOutput` and `haproxy`
becomes `Haproxy`. Make sure your class name is correct.
