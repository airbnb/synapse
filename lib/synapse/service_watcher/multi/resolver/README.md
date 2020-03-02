# Resolvers

A resolver decides how to combine, or resolve, multiple service watchers into a
single result. That is, it operates as a `reducer` function to allow more than
one service watchers to appear, and act, as a single watcher.

The stub methods listed below should be overridden by any children classes.
If any additional methods are overridden (such as `initialize`), be sure to
call `super` first.

```ruby
require "synapse/service_watcher/multi/resolver/base"

class Synapse::ServiceWatcher::MultiWatcher::Resolver
   class MyResolver < BaseResolver
      def start
	     # start resolver
	  end

	  def stop
	     # stop resolver
	  end

	  def backends
	     # return a single list of backends
	  end

	  def ping?
	     # return whether or not the watchers are healthy
	  end
   end
end
```

### Resolver Plugin Interface
Synapse deduces both the class path and class name from the `method` key within
the resolver configuration.  Every resolver is passed configuration with the
`method` key, e.g. `zookeeper` or `ec2tag`.

#### Class Location
Synapse expects to find your class at `synapse/service_watcher/multi/#{method}`.
You must make your resolver available at that path, and Synapse can "just work" and
find it.

#### Class Name
These method strings are then transformed into class names via the following
function:

```
method_class  = method.split('_').map{|x| x.capitalize}.join.concat('Resolver')
```

This has the effect of taking the method, splitting on '_', capitalizing each
part and recombining with an added 'Resolver' on the end. So `fallback`
becomes `FallbackResolver`, and `union` becomes `UnionResolver`. Make sure
your class name is correct.
