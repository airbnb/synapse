## Watcher Classes

Watchers are the piece of Synapse that watch an external service registry
and reflect those changes in the local configuration state. Watchers should
conform to the interface specified by `BaseWatcher` and when your watcher has
received an update from the service registry you should call
`set_backends(new_backends)` to trigger a sync of your watcher state with local
configuration (HAProxy, files, etc ...) state. See the
[`Backend Interface`](#backend_interface) section for what fields in
registrations Synapse understands.

```ruby
require "synapse/service_watcher/base"

class Synapse::ServiceWatcher
  class MyWatcher < BaseWatcher
    def start
      # write code which begins running service discovery
    end

    def stop
      # write code which tears down the service discovery
    end

    def ping?
      # write code to check in on the health of the watcher
    end

    private
    def validate_discovery_opts
      # here, validate any required options in @discovery
    end

    ... setup watches, poll, etc ... and call set_backends when you have new
    ... backends to set

  end
end
```

### Watcher Plugin Inteface
Synapse deduces both the class path and class name from the `method` key within
the watcher configuration.  Every watcher is passed configuration with the
`method` key, e.g. `zookeeper` or `ec2tag`.

#### Class Location
Synapse expects to find your class at `synapse/service_watcher/#{method}`. You
must make your watcher available at that path, and Synapse can "just work" and
find it.

#### Class Name
These method strings are then transformed into class names via the following
function:

```
method_class  = method.split('_').map{|x| x.capitalize}.join.concat('Watcher')
```

This has the effect of taking the method, splitting on '_', capitalizing each
part and recombining with an added 'Watcher' on the end. So `zookeeper_dns`
becomes `ZookeeperDnsWatcher`, and `zookeeper` becomes `Zookeeper`. Make sure
your class name is correct.

<a name="backend_interface"/>
### Backend interface
Synapse understands the following fields in service backends (which are pulled
from the service registries):

`host` (string): The hostname of the service instance

`port` (integer): The port running the service on `host`

`name` (string, optional): The human readable name to refer to this service instance by

`weight` (float, optional): The weight that this backend should get when load
balancing to this service instance. Full support for updating HAProxy based on
this is still a WIP.

`haproxy_server_options` (string, optional): Any haproxy server options
specific to this particular server. They will be applied to the generated
`server` line in the HAProxy configuration. If you want Synapse to react to
changes in these lines you will need to enable the `state_file_path` option
in the main synapse configuration. In general the HAProxy backend level
`haproxy.server_options` setting is preferred to setting this per server
in your backends.
