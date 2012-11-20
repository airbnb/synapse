require 'bundler'
Bundler.require

require "yaml"

if $0 == __FILE__
  # parse synapse config file
  config = YAML::load_file("synapse.conf.yaml")

  # generate stats hash
  stats = {
    'started'=>Time.now(),
    'services'=>{},
  }

  config['services'].each do |service|
    stats['services'][service['name']] = {
      'updated'=>0,
      'disappeared_hosts'=>[],
      'current_hosts'=>service['default_servers'] ? service['default_servers'] : [],
    }
  end

  # turn on the enbedded web daemon

  # initialize service watchers

  # generate the haproxy config

  # force a haproxy start/restart

  # enable the callback to reload haproxy
end
