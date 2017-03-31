[![Build Status](https://travis-ci.org/airbnb/synapse.png?branch=master)](https://travis-ci.org/airbnb/synapse)
[![Inline docs](http://inch-ci.org/github/airbnb/synapse.png)](http://inch-ci.org/github/airbnb/synapse)

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
* ELB: ultimately uses DNS (see above), can't tune load balancing, have to launch a new one for every service * region, autoscaling doesn't happen fast enough

One solution to this problem is a discovery service, like [Apache Zookeeper](http://zookeeper.apache.org/).
However, Zookeeper and similar services have their own problems:

* Service discovery is embedded in all of your apps; often, integration is not simple
* The discovery layer itself is subject to failure
* Requires additional servers/instances

Synapse solves these difficulties in a simple and fault-tolerant way.

## How Synapse Works ##

Synapse typically runs on your application servers, often every machine. At the heart of Synapse
are proven routing components like [HAProxy](http://haproxy.1wt.eu/) or [NGINX](http://nginx.org/).

For every external service that your application talks to, we assign a synapse local port on localhost.
Synapse creates a proxy from the local port to the service, and you reconfigure your application to talk to the proxy.

Under the hood, Synapse sports `service_watcher`s for service discovery and
`config_generators` for configuring local state (e.g. load balancer configs)
based on that service discovery state.

Synapse supports service discovery with with pluggable `service_watcher`s which
take care of signaling to the `config_generators` so that they can react and
reconfigure to point at available servers on the fly.

We've included a number of default watchers, including ones that query zookeeper and ones using the AWS API.
It is easy to write your own watchers for your use case, and install them as gems that
extend Synapse's functionality. Check out the [docs](#createsw) on creating
a watcher if you're interested, and if you think that the service watcher
would be generally useful feel free to pull request with a link to your watcher.

Synapse also has pluggable `config_generator`s, which are responsible for reacting to service discovery
changes and writing out appropriate config. Right now HAProxy, and local files are built in, but you
can plug your own in [easily](#createconfig).

## Example Migration ##

Let's suppose your rails application depends on a Postgres database instance.
The database.yaml file has the DB host and port hardcoded:

```yaml
production:
  database: mydb
  host: mydb.example.com
  port: 5432
```

You would like to be able to fail over to a different database in case the original dies.
Let's suppose your instance is running in AWS and you're using the tag 'proddb' set to 'true' to indicate the prod DB.
You set up synapse to proxy the DB connection on `localhost:3219` in the `synapse.conf.yaml` file.
Add a hash under `services` that looks like this:

```yaml
---
 services:
  proddb:
   default_servers:
    -
     name: "default-db"
     host: "mydb.example.com"
     port: 5432
   discovery:
    method: "awstag"
    tag_name: "proddb"
    tag_value: "true"
   haproxy:
    port: 3219
    server_options: "check inter 2000 rise 3 fall 2"
    frontend: mode tcp
    backend: mode tcp
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

To download and run the synapse binary, first install a version of ruby. Then,
install synapse with:

```bash
$ mkdir -p /opt/smartstack/synapse
# If you are on Ruby 2.X use --no-document instead of --no-ri --no-rdoc

# If you want to install specific versions of dependencies such as an older
# version of the aws-sdk, the docker-api, etc, gem install that here *before*
# gem installing synapse.

# Example:
# $ gem install aws-sdk -v XXX

$ gem install synapse --install-dir /opt/smartstack/synapse --no-ri --no-rdoc

# If you want to install specific plugins such as watchers or config generators
# gem install them *after* you install synapse.

# Example:
# $ gem install synapse-nginx --install-dir /opt/smartstack/synapse --no-ri --no-rdoc
```

This will download synapse and its dependencies into /opt/smartstack/synapse. You
might wish to omit the `--install-dir` flag to use your system's default gem
path, however this will require you to run `gem install synapse` with root
permissions.

You can now run the synapse binary like:

```bash
export GEM_PATH=/opt/smartstack/synapse
/opt/smartstack/synapse/bin/synapse --help
```

Don't forget to install HAProxy or NGINX or whatever proxy your `config_generator`
is configuring.

## Configuration ##

Synapse depends on a single config file in JSON format; it's usually called `synapse.conf.json`.
The file has a `services` section that describes how services are discovered
and configured, and then top level sections for every supported proxy or
configuration section. For example, the default Synapse supports three sections:

* [`services`](#services): lists the services you'd like to connect.
* [`haproxy`](#haproxy): specifies how to configure and interact with HAProxy.
* [`file_output`](#file) (optional): specifies where to write service state to on the filesystem.
* [`<your config generator here>`] (optional): configuration for your custom
   configuration generators (e.g. nginx, vulcand, envoy, etc ..., w.e. you want).

If you have synapse `config_generator` plugins installed, you'll want a top
level as well, e.g.:
* [`nginx`](https://github.com/jolynch/synapse-nginx#top-level-config) (optional):
  configuration for how to configure and interact with NGINX.

<a name="services"/>

### Configuring a Service ###

The `services` section is a hash, where the keys are the `name` of the service to be configured.
The name is just a human-readable string; it will be used in logs and notifications.
Each value in the services hash is also a hash, and must contain the following keys:

* [`discovery`](#discovery): how synapse will discover hosts providing this service (see [below](#discovery))

The services hash *should* contain a section on how to configure each routing
component you wish to use for this particular service. The current choices are
`haproxy` but you can access others e.g. [`nginx`](https://github.com/jolynch/synapse-nginx)
through [plugins](createconfig). Note that if you give a routing component at the top level
but not at the service level the default is typically to make that service
available via that routing component, sans listening ports. If you wish to only
configure a single component explicitly pass the ``disabled`` option to the
relevant routing component. For example if you want to only configure HAProxy and
not NGINX for a particular service, you would pass ``disabled`` to the `nginx` section
of that service's watcher config.

* [`haproxy`](#haproxysvc): how will the haproxy section for this service be configured
* [`nginx`](https://github.com/jolynch/synapse-nginx#service-watcher-config): how will the nginx section for this service be configured. **NOTE** to use this you must have the synapse-nginx [plugin](#plugins) installed.

The services hash may contain the following additional keys:

* `default_servers` (default: `[]`): the list of default servers providing this service; synapse uses these if no others can be discovered. See [Listing Default Servers](#defaultservers).
* `keep_default_servers` (default: false): whether default servers should be added to discovered services
* `use_previous_backends` (default: true): if at any time the registry drops all backends, use previous backends we already know about.
<a name="backend_port_override"/>
* `backend_port_override`: the port that discovered servers listen on; you should specify this if your discovery mechanism only discovers names or addresses (like the DNS watcher or the Ec2TagWatcher). If the discovery method discovers a port along with hostnames (like the zookeeper watcher) this option may be left out, but will be used in preference if given.

<a name="discovery"/>

#### Service Discovery ####

We've included a number of `watchers` which provide service discovery.
Put these into the `discovery` section of the service hash, with these options:

##### Base #####

The base watcher is useful in situations where you only want to use the servers in the `default_servers` list.
It has the following options:

* `method`: base
* `label_filters`: optional list of filters to be applied to discovered service nodes

###### Filtering service nodes ######

Synapse can be configured to only return service nodes that match a `label_filters` predicate. If provided, `label_filters` should be an array of hashes which contain the following:

* `label`: The name of the label for which the filter is applied
* `value`: The comparison value
* `condition` (one of ['`equals`', '`not-equals`']): The type of filter condition to be applied.

Given a `label_filters`: `[{ "label": "cluster", "value": "dev", "condition": "equals" }]`, this will return only service nodes that contain the label value `{ "cluster": "dev" }`.

##### Zookeeper #####

This watcher retrieves a list of servers from zookeeper.
It takes the following mandatory arguments:

* `method`: zookeeper
* `path`: the zookeeper path where ephemeral nodes will be created for each available service server
* `hosts`: the list of zookeeper servers to query

The watcher assumes that each node under `path` represents a service server.

The following arguments are optional:

* `decode`: A hash containing configuration for how to decode the data found in zookeeper.

###### Decoding service nodes ######
Synapse attempts to decode the data in each of these nodes using JSON and you can control how it is decoded with the `decode` argument. If provided, the `decode` hash should contain the following:

* `method` (one of ['`nerve`', '`serverset`'], default: '`nerve`'): The kind of data to expect to find in zookeeper nodes
* `endpoint_name` (default: nil): If using the `serverset` method, this controls which of the `additionalEndpoints` is chosen instead of the `serviceEndpoint` data. If not supplied the `serverset` method will use the host/port from the `serviceEndpoint` data.

If the `method` is `nerve`, then we expect to find nerve registrations with a `host` and a `port`.
Any additional metadata for the service node provided in the hash `labels` will be parsed. This information is used by `label_filter` configuration.

If the `method` is `serverset` then we expect to find Finagle ServerSet
(also used by [Aurora](https://github.com/apache/aurora/blob/master/docs/user-guide.md#service-discovery)) registrations with a `serviceEndpoint` and optionally one or more `additionalEndpoints`.
The Synapse `name` will be automatically deduced from `shard` if present.

##### Docker #####

This watcher retrieves a list of [docker](http://www.docker.io/) containers via docker's [HTTP API](http://docs.docker.io/en/latest/reference/api/docker_remote_api/).
It takes the following options:

* `method`: docker
* `servers`: a list of servers running docker as a daemon. Format is `{"name":"...", "host": "..."[, port: 4243]}`
* `image_name`: find containers running this image
* `container_port`: find containers forwarding this port
* `check_interval`: how often to poll the docker API on each server. Default is 15s.

##### AWS EC2 tags #####

This watcher retrieves a list of Amazon EC2 instances that have a tag
with particular value using the AWS API.
It takes the following options:

* `method`: ec2tag
* `tag_name`: the name of the tag to inspect. As per the AWS docs,
  this is case-sensitive.
* `tag_value`: the value to match on. Case-sensitive.

Additionally, you MUST supply [`backend_port_override`](#backend_port_override)
in the service configuration as this watcher does not know which port the
backend service is listening on.

The following options are optional, provided the well-known `AWS_`
environment variables shown are set. If supplied, these options will
be used in preference to the `AWS_` environment variables.

* `aws_access_key_id`: AWS key or set `AWS_ACCESS_KEY_ID` in the environment.
* `aws_secret_access_key`: AWS secret key or set `AWS_SECRET_ACCESS_KEY` in the environment.
* `aws_region`: AWS region (i.e. `us-east-1`) or set `AWS_REGION` in the environment.

##### Marathon #####

This watcher polls the Marathon API and retrieves a list of instances for a
given application.

It takes the following options:

* `marathon_api_url`: Address of the marathon API (e.g. `http://marathon-master:8080`)
* `application_name`: Name of the application in Marathon
* `check_interval`: How often to request the list of tasks from Marathon (default: 10 seconds)
* `port_index`: Index of the backend port in the task's "ports" array. (default: 0)

<a name="defaultservers"/>

#### Listing Default Servers ####

You may list a number of default servers providing a service.
Each hash in that section has the following options:

* `name`: a human-readable name for the default server; must be unique
* `host`: the host or IP address of the server
* `port`: the port where the service runs on the `host`

The `default_servers` list is used only when service discovery returns no servers.
In that case, the service proxy will be created with the servers listed here.
If you do not list any default servers, no proxy will be created.  The
`default_servers` will also be used in addition to discovered servers if the
`keep_default_servers` option is set.

If you do not list any `default_servers`, and all backends for a service
disappear then the previous known backends will be used.  Disable this behavior
by unsetting `use_previous_backends`.

<a name="haproxysvc"/>

#### The `haproxy` Section ####

This section is its own hash, which should contain the following keys:

* `disabled`: A boolean value indicating if haproxy configuration management
for just this service instance ought be disabled. For example, if you want
file output for a particular service but no HAProxy config. (default is ``False``)
* `port`: the port (on localhost) where HAProxy will listen for connections to
the service. If this is null, just the bind_address will be used (e.g. for
unix sockets) and if omitted, only a backend stanza (and no frontend stanza)
will be generated for this service. In the case of a bare backend, you'll need
to get traffic to your service yourself via the `shared_frontend` or
manual frontends in `extra_sections`
* `bind_address`: force HAProxy to listen on this address (default is localhost).
Setting `bind_address` on a per service basis overrides the global `bind_address`
in the top level `haproxy`. Having HAProxy listen for connections on
different addresses (example: service1 listen on 127.0.0.2:443 and service2
listen on 127.0.0.3:443) allows /etc/hosts entries to point to services.
* `bind_options`: optional: default value is an empty string, specify additional bind parameters, such as ssl accept-proxy, crt, ciphers etc.
* `server_port_override`: **DEPRECATED**. Renamed [`backend_port_override`](#backend_port_override) and moved to the top level hash. This will be removed in future versions.
* `server_options`: the haproxy options for each `server` line of the service in HAProxy config; it may be left out.
* `frontend`: additional lines passed to the HAProxy config in the `frontend` stanza of this service
* `backend`: additional lines passed to the HAProxy config in the `backend` stanza of this service
* `backend_name`: The name of the generated HAProxy backend for this service
  (defaults to the service's key in the `services` section)
* `listen`: these lines will be parsed and placed in the correct `frontend`/`backend` section as applicable; you can put lines which are the same for the frontend and backend here.
* `backend_order`: optional: how backends should be ordered in the `backend` stanza. (default is shuffling). Setting to `asc` means sorting backends in ascending alphabetical order before generating stanza. `desc` means descending alphabetical order. `no_shuffle` means no shuffling or sorting.
* `shared_frontend`: optional: haproxy configuration directives for a shared http frontend (see below)
* `cookie_value_method`: optional: default value is `name`, it defines the way your backends receive a cookie value in http mode. If equal to `hash`, synapse hashes backend names on cookie value assignation of your discovered backends, useful when you want to use haproxy cookie feature but you do not want that your end users receive a Set-Cookie with your server name and ip readable in clear.

<a name="haproxy"/>

### Configuring HAProxy ###

The top level `haproxy` section of the config file has the following options:

* `reload_command`: the command Synapse will run to reload HAProxy
* `config_file_path`: where Synapse will write the HAProxy config file
* `do_writes`: whether or not the config file will be written (default to `true`)
* `do_reloads`: whether or not Synapse will reload HAProxy (default to `true`)
* `do_socket`: whether or not Synapse will use the HAProxy socket commands to prevent reloads (default to `true`)
* `socket_file_path`: where to find the haproxy stats socket. can be a list (if using `nbproc`)
* `global`: options listed here will be written into the `global` section of the HAProxy config
* `defaults`: options listed here will be written into the `defaults` section of the HAProxy config
* `extra_sections`: additional, manually-configured `frontend`, `backend`, or `listen` stanzas
* `bind_address`: force HAProxy to listen on this address (default is localhost)
* `shared_frontend`: (OPTIONAL) additional lines passed to the HAProxy config used to configure a shared HTTP frontend (see below)
* `restart_interval`: number of seconds to wait between restarts of haproxy (default: 2)
* `restart_jitter`: percentage, expressed as a float, of jitter to multiply the `restart_interval` by when determining the next
  restart time. Use this to help prevent healthcheck storms when HAProxy restarts. (default: 0.0)
* `state_file_path`: full path on disk (e.g. /tmp/synapse/state.json) for
  caching haproxy state between reloads.  If provided, synapse will store
  recently seen backends at this location and can "remember" backends across
  both synapse and HAProxy restarts. Any backends that are "down" in the
  reporter but listed in the cache will be put into HAProxy disabled. Synapse
  writes the state file every sixty seconds, so the file's age can be used to
  monitor that Synapse is alive and making progress. (default: nil)
* `state_file_ttl`: the number of seconds that backends should be kept in the
  state file cache.  This only applies if `state_file_path` is provided.
  (default: 86400)

Note that a non-default `bind_address` can be dangerous.
If you configure an `address:port` combination that is already in use on the system, haproxy will fail to start.

<a name="file"/>

### Configuring `file_output` ###

This section controls whether or not synapse will write out service state
to the filesystem in json format. This can be used for services that want to
use discovery information but not go through HAProxy.

* `output_directory`: the path to a directory on disk that service registrations
should be written to.

### HAProxy shared HTTP Frontend ###

For HTTP-only services, it is not always necessary or desirable to dedicate a TCP port per service, since HAProxy can route traffic based on host headers.
To support this, the optional `shared_frontend` section can be added to both the `haproxy` section and each indvidual service definition.
Synapse will concatenate them all into a single frontend section in the generated haproxy.cfg file.
Note that synapse does not assemble the routing ACLs for you; you have to do that yourself based on your needs.
This is probably most useful in combination with the `service_conf_dir` directive in a case where the individual service config files are being distributed by a configuration manager such as puppet or chef, or bundled into service packages.
For example:

```yaml
 haproxy:
  shared_frontend:
   - "bind 127.0.0.1:8081"
  reload_command: "service haproxy reload"
  config_file_path: "/etc/haproxy/haproxy.cfg"
  socket_file_path:
    - /var/run/haproxy.sock
    - /var/run/haproxy2.sock
  global:
   - "daemon"
   - "user    haproxy"
   - "group   haproxy"
   - "maxconn 4096"
   - "log     127.0.0.1 local2 notice"
   - "stats   socket /var/run/haproxy.sock"
  defaults:
   - "log      global"
   - "balance  roundrobin"
 services:
  service1:
   discovery: 
    method: "zookeeper"
    path:  "/nerve/services/service1"
    hosts:
     - "0.zookeeper.example.com:2181"
   haproxy:
    server_options: "check inter 2s rise 3 fall 2"
    shared_frontend:
     - "acl is_service1 hdr_dom(host) -i service1.lb.example.com"
     - "use_backend service1 if is_service1"
    backend: "mode http"

  service2:
   discovery:
    method: "zookeeper"
    path:  "/nerve/services/service2"
    hosts: "0.zookeeper.example.com:2181"

   haproxy:
    server_options: "check inter 2s rise 3 fall 2"
    shared_frontend:
     - "acl is_service1 hdr_dom(host) -i service2.lb.example.com"
     - "use_backend service2 if is_service2"
    backend:
     - "mode http"

```

This would produce an haproxy.cfg much like the following:

```
backend service1
        mode http
        server server1.example.net:80 server1.example.net:80 check inter 2s rise 3 fall 2

backend service2
        mode http
        server server2.example.net:80 server2.example.net:80 check inter 2s rise 3 fall 2

frontend shared-frontend
        bind 127.0.0.1:8081
        acl is_service1 hdr_dom(host) -i service1.lb
        use_backend service1 if is_service1
        acl is_service2 hdr_dom(host) -i service2.lb
        use_backend service2 if is_service2
```

Non-HTTP backends such as MySQL or RabbitMQ will obviously continue to need their own dedicated ports.

## Contributing
Note that now that we have a fully dynamic include system for service watchers
and configuration generators, you don't *have* to PR into the main tree, but
please do contribute a [link](#plugins).

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

<a name="createsw"/>

### Creating a Service Watcher ###

See the Service Watcher [README](lib/synapse/service_watcher/README.md) for
how to add new Service Watchers.

<a name="createconfig"/>

### Creating a Config Generator ###

See the Config Generator [README](lib/synapse/config_generator/README.md) for
how to add new Config Generators

<a name="plugins"/>

## Links to Synapse Plugins ##
* [`synapse-nginx`](https://github.com/jolynch/synapse-nginx) Is a `config_generator`
  which allows Synapse to automatically configure and administer a local NGINX
  proxy.
