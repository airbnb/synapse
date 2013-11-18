# Synapse #

Synapse is Airbnb's new system for service discovery.
Synapse solves the problem of automated fail-over in the cloud, where failover via network re-configuration is impossible.
The end result is the ability to connect internal services together in a scalable, fault-tolerant way.

## Motivation ##

Synapse emerged from the need to maintain high-availability applications in the cloud.
Traditional high-availability techniques, which involve using a CRM like [pacemaker](http://linux-ha.org/wiki/Pacemaker), do not work in environments where the end-user has no control over the networking.
In an environment like Amazon's EC2, all of the available workarounds are suboptimal:

* Round-robin DNS: Slow to converge, and doesn't work when applications cache DNS lookups (which is frequent)
* Elastic IPs: slow to converge, limited in number, public-facing-only, which makes them less useful for internal services
* ELB: Again, public-facing only, and only useful for HTTP

One solution to this problem is a discovery service, like [Apache Zookeeper](http://zookeeper.apache.org/).
However, Zookeeper and similar services have their own problems:

* Service discovery is embedded in all of your apps; often, integration is not simple
* The discovery layer itself it subject to failure
* Requires additional servers/instances

Synapse solves these difficulties in a simple and fault-tolerant way.

## How Synapse Works ##

Synapse runs on your application servers; here at Airbnb, we just run it on every box we deploy.
The heart of synapse is actually [HAProxy](http://haproxy.1wt.eu/), a stable and proven routing component.
For every external service that your application talks to, we assign a synapse local port on localhost.
Synapse creates a proxy from the local port to the service, and you reconfigure your application to talk to the proxy.

Synapse comes with a number of `watchers`, which are responsible for service discovery.
The synapse watchers take care of re-configuring the proxy so that it always points at available servers.
We've included a number of default watchers, including ones that query zookeeper and ones using the AWS API.
It is easy to write your own watchers for your use case, and we encourage submitting them back to the project.

## Example Migration ##

Lets suppose your rails application depends on a Postgre database instance.
The database.yaml file has the DB host and port hardcoded:

```yaml
production:
  database: mydb
  host: mydb.example.com
  port: 5432
```

You would like to be able to fail over to a different database in case the original dies.
Let's suppose your instance is running in AWS and you're using the tag 'proddb' set to 'true' to indicate the prod DB.
You set up synapse to proxy the DB connection on `localhost:3219` in the `synapse.conf.json` file.
Add a hash under `services` that looks like this:

```json
{"services":
    "proddb": {
      "default_servers": [
        {
          "name": "default-db",
          "host": "mydb.example.com",
          "port": 5432
        }
      ],
      "discovery": {
        "method": "awstag",
        "tag": "proddb",
        "value": "true"
      },
      "haproxy": {
        "port": 3219,
        "server_options": "check inter 2000 rise 3 fall 2",
        "frontend": [
          "mode tcp",
        ],
        "backend": [
          "mode tcp",
        ],
      },
    },
...
```

And then change your database.yaml file to look like this:

```yaml
production:
  database: mydb
  host: localhost
  port: 3219
```

Start up synapse.
It will configure HAProxy with a proxy from `localhost:3219` to your DB.
It will attempt to find the DB using the AWS API; if that does not work, it will default to the DB given in `default_servers`.
In the worst case, if AWS API is down and you need to change which DB your application talks to, simply edit the `synapse.conf.json` file, update the `default_servers` and restart synapse.
HAProxy will be transparently reloaded, and your application will keep running without a hiccup.

## Installation

Add this line to your application's Gemfile:

    gem 'synapse'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install synapse

## Configuration ##

Synapse depends on a single config file in JSON format; it's usually called `synapse.conf.json`.
The file has two main sections.
The first is the `services` section, which lists the services you'd like to connect.
The second is the `haproxy` section, which specifies how to configure and interact with HAProxy.

### Configuring a Service ###

The services are a hash, where the keys are the `name` of the service to be configured.
The name is just a human-readable string; it will be used in logs and notifications.
Each value in the services hash is also a hash, and should contain the following keys:

* `discovery`: how synapse will discover hosts providing this service (see below)
* `default_servers`: the list of default servers providing this service; synapse uses these if none others can be discovered
* `haproxy`: how will the haproxy section for this service be configured

#### Service Discovery ####

We've included a number of `watchers` which provide service discovery.
Put these into the `discovery` section of the service hash, with these options:

##### Stub #####

The stub watcher, this is useful in situations where you only want to use the servers in the `default_servers` list.
It has only one option:

* `method`: stub

##### Zookeeper #####

This watcher retrieves a list of servers from zookeeper.
It takes the following options:

* `method`: zookeeper
* `path`: the zookeeper path where ephemeral nodes will be created for each available service server
* `hosts`: the list of zookeeper servers to query

The watcher assumes that each node under `path` represents a service server.
Synapse attempts to decode the data in each of these nodes using JSON and also using Thrift under the standard Twitter service encoding.
We assume that the data contains a hostname and a port for service servers.

##### Docker #####

This watcher retrieves a list of [docker](http://www.docker.io/) containers via docker's [HTTP API](http://docs.docker.io/en/latest/api/docker_remote_api/).
It takes the following options:

* `method`: docker
* `servers`: a list of servers running docker as a daemon. Format is `{"name":"...", "host": "..."[, port: 4243]}`
* `image_name`: find containers running this image
* `container_port`: find containers forwarding this port
* `check_interval`: how often to poll the docker API on each server. Default is 15s.

#### Listing Default Servers ####

You may list a number of default servers providing a service.
Each hash in that section has the following options:

* `name`: a human-readable name for the default server; must be unique
* `host`: the host or IP address of the server
* `port`: the port where the service runs on the `host`

The `default_servers` list is used only when service discovery returns no servers.
In that case, the service proxy will be created with the servers listed here.
If you do not list any default servers, no proxy will be created.

#### The `haproxy` Section ####

This section is it's own hash, which should contain the following keys:

* `port`: the port (on localhost) where HAProxy will listen for connections to the service.
* `server_port_override`: the port that discovered servers listen on; you should specify this if your discovery mechanism only discovers names or addresses (like the DNS watcher). If the discovery method discovers a port along with hostnames (like the zookeeper watcher) this option may be left out, but will be used in preference if given.
* `server_options`: the haproxy options for each `server` line of the service in HAProxy config; it may be left out.
* `frontend`: additional lines passed to the HAProxy config in the `frontend` stanza of this service
* `backend`: additional lines passed to the HAProxy config in the `backend` stanza of this service
* `listen`: these lines will be parsed and placed in the correct `frontend`/`backend` section as applicable; you can put lines which are the same for the frontend and backend here.

### Configuring HAProxy ###

The `haproxy` section of the config file has the following options:

* `reload_command`: the command Synapse will run to reload HAProxy
* `config_file_path`: where Synapse will write the HAProxy config file
* `do_writes`: whether or not the config file will be written (default to `true`)
* `do_reloads`: whether or not Synapse will reload HAProxy (default to `true`)
* `global`: options listed here will be written into the `global` section of the HAProxy config
* `defaults`: options listed here will be written into the `defaults` section of the HAProxy config

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

### Creating a Service Watcher ###

If you'd like to create a new service watcher:

1. Create a file for your watcher in `service_watcher` dir
2. Use the following template:
```ruby
require_relative "./base"
module Synapse
  class NewWatcher < BaseWatcher
    def start
      # write code which begins running service discovery
    end

    private
    def validate_discovery_opts
      # here, validate any required options in @discovery
    end
  end
end
```

3. Implement the `start` and `validate_discovery_opts` methods
4. Implement whatever additional methods your discovery requires

When your watcher detects a list of new backends, they should be written to `@backends`.
You should then call `@synapse.configure` to force synapse to update the HAProxy config.
