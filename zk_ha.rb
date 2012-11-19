require 'rubygems'
require 'bundler'

Bundler.require

$:.unshift('./lib')

require 'service_watcher'
require 'haproxy_config'
require 'gen-rb/endpoint_types'


haproxy_bin = '/usr/local/sbin/haproxy'
haproxy_cfg = 'config/haproxy.cfg'
haproxy_pid = 'haproxy.pid'


if $0 == __FILE__
  config = HaproxyConfig.new

  ServiceWatcher.new('/airbnb/service/search/nodes') do |instances|
    # Transform for the template
    nodes = instances.map do |node|
      host = node.serviceEndpoint.host
      port = node.serviceEndpoint.port
      {host: host, port: port, name: "#{host}:#{port}"}
    end

    config.set_nodes('search', nodes)
    p nodes

    # Write new config
    File.open(haproxy_cfg, 'w') do |f|
      f.puts(config.render)
    end

    # Reload HAProxy
    pid = File.read(haproxy_pid).chomp
    puts "reloading HAProxy with PID #{pid}"

    cmd = "#{haproxy_bin} -f #{haproxy_cfg} -sf #{pid}"
    p cmd
    system cmd
  end

  loop do
    sleep 1
    p Time.now
  end
end
