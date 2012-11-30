# Synapse #

Synapse is AirBnB's new system for service discovery.
Synapse solves the problem of automated fail-over in the cloud, where failover via network re-configuration is impossible.
The end result is the ability to connect internal services together in a scalable, fault-tolerant way.

## Motivation ##

In traditional data centers, the standard way of doing failover is via network reconfiguration.
Suppose you have the following network diagram:

```
    ------      ------     ------ 
   | App1 |    | App2 |   | App3 |
    ------      ------     ------ 
      |           |          |
      |           |          |
      -----------------------
            |
       -----------      -------------
      | DB-Master |----| DB-Failover |
       -----------      -------------
```

When `DB-Master` fails, you want your `App` servers to begin talking to `DB-Failover`.
Traditionally, you detect the failure using a monitoring system like [heartbeat](http://linux-ha.org/wiki/Heartbeat).
You then recover from the failure using a CRM like [pacemaker](http://linux-ha.org/wiki/Pacemaker).
Using the example of a DB, pacemaker would STONITH `DB-Master` to ensure data integrity and then move the IP of `DB-Master` to `DB-Failover`.
After the failure, the cluster would look like this:

```
    ------      ------     ------ 
   | App1 |    | App2 |   | App3 |
    ------      ------     ------ 
      |           |          |
      |           |          |
      -----------------------
                          |       
                        ------------- 
                       | DB-Failover |
                        ------------- 
```

This kind of approach is impossible in a cloud environment like amazon's EC2.
User applications there do not have control over IP addresses assigned to nodes, and so cannot

## Installation

Add this line to your application's Gemfile:

    gem 'synapse'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install synapse

## Usage

Write usage instructions here

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
