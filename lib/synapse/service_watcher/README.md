Please, do not submit pull requests with new watchers, as Synapse and Nerve
both support a plugin system for adding watchers and reporters respectively.

## Watcher Classes

Watchers are the piece of Synapse that watch an external service registry
and reflect those changes in the local HAProxy state. Watchers should look
like:

```
require "synapse/service\_watcher/base"

module Synapse::ServiceWatcher
  class MyWatcher < BaseWatcher
  ...
  end
end
```

### Watcher Plugin Inteface
Synapse deduces both the class path and class name from the `method` key within
the watcher configuration.  Every watcher is passed configuration with the
`method` key, e.g. `zookeeper` or `ec2tag`.

#### Class Location
Synapse expects to find your class at `synapse/service\_watcher/#{method}`. You
must make your watcher available at that path, and Synapse can "just work" and
find it.

#### Class Name
These method strings are then transformed into class names via the following
function:

```
method_class  = method.split('_').map{|x| x.capitalize}.join.concat('Watcher')
```

This has the effect of taking the method, splitting on '_', capitalizing each
part and recombining with an added 'Watcher' on the end. So `zookeeper\_dns`
becomes `ZookeeperDnsWatcher`, and `zookeeper` becomes `Zookeeper`. Make sure
your class name is correct.

### Watcher Class Interface
ServiceWatchers should conform to the interface provided by `BaseWatcher`:

```
start: start the watcher on a service registry

stop: stop the watcher on a service registry

ping?: healthcheck the watcher's connection to the service registry

validate_discovery_opts: check if the configuration has the right options
```

When your watcher has received an update from the service registry you should
call `set\_backends(new\_backends)` to trigger a sync of your watcher state
with local HAProxy state.
