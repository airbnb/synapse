require 'spec_helper'
require 'tempfile'
require 'synapse/service_watcher/multi'

describe 'parseconfig' do
  it 'parses a templated config' do
    allow_any_instance_of(Synapse::Synapse).to receive(:run)
    expect(Synapse::Synapse).to receive(:new).
      with(hash_including(
       {"services" =>
          {"test" =>
            {"default_servers" =>
              [{"name" => "default1", "host" => "localhost", "port" => 8080}],
             "discovery" =>
              {"method" => "zookeeper",
               "path" => "/airbnb/service/logging/event_collector",
               "hosts" => ["localhost:2181"],
               "label_filters" =>
                [{"label" => "tag", "value" => "config value", "condition" => "equals"}]},
             "haproxy" =>
              {"port" => 3219,
               "bind_address" => "localhost",
               "server_options" => ["some_haproxy_server_option"],
               "listen" => ["some_haproxy_listen_option"]}}},
         "haproxy" =>
          {"reload_command" => "sudo service haproxy reload",
           "config_file_path" => "/etc/haproxy/haproxy.cfg",
           "do_writes" => false,
           "do_reloads" => false,
           "do_socket" => false,
           "global" => ["global_test_option"],
           "defaults" => ["default_test_option"]},
         "file_output" => {"output_directory" => "/tmp/synapse_file_output_test"}}
      )).and_call_original
    stub_const 'ENV', ENV.to_hash.merge(
      {"SYNAPSE_CONFIG" => "#{File.dirname(__FILE__)}/../support/minimum.conf.yaml",
      "SYNAPSE_CONFIG_VALUE" => "config value"}
    )
    stub_const 'ARGV', []
    load "#{File.dirname(__FILE__)}/../../bin/synapse"
  end

  it 'fails if templated config is invalid' do
    allow_any_instance_of(Synapse::Synapse).to receive(:run)
    tmpcfg = Tempfile.new 'synapse.conf.yaml'
    tmpcfg.write '{:a => "<% if %>"}'
    tmpcfg.flush
    stub_const 'ENV', ENV.to_hash.merge(
      {"SYNAPSE_CONFIG" => tmpcfg.to_path,
      "SYNAPSE_CONFIG_VALUE" => "config value"}
    )
    stub_const 'ARGV', []
    expect {
      load "#{File.dirname(__FILE__)}/../../bin/synapse"
    }.to raise_error(SyntaxError)
  end

  it 'parses discovery_multi configuration properly' do
    allow_any_instance_of(Synapse::Synapse).to receive(:run)

    expect(Synapse::Synapse).to receive(:new).exactly(:once).and_call_original
    expect(Synapse::ServiceWatcher::MultiWatcher)
      .to receive(:new)
      .exactly(:once)
      .with({"discovery" => {
               "method" => "multi",
               "resolver" => {
                 "method" => "fallback",
               },
               "watchers" => {
                 "primary" => {
                   "method" => "zookeeper",
                   "path" => "/services/service1",
                   "discovery_jitter" => 25,
                   "hosts" => ["localhost:2181", "localhost:2182", "localhost:2183"],
                 },
                 "secondary" => {
                   "method" => "zookeeper",
                   "path" => "/services/service1",
                   "discovery_jitter" => 5,
                   "hosts" => ["localhost:2184", "localhost:2185", "localhost:2186"],
                 },
               }
             },
             "haproxy" => {
               "port" => 3213,
               "server_options" => "check inter 2s rise 3 fall 2",
               "bind_options" => "ssl no-sslv3 crt /path/to/cert/example.pem ciphers ECDHE-ECDSA-CHACHA20-POLY1305",
               "listen" => [
                 "mode http",
                 "option httpchk /health",
                 "http-check expect string OK",
               ]
             },
            "name" => "service1"}, instance_of(Synapse::Synapse), duck_type(:call))

    stub_const 'ENV', ENV.to_hash.merge(
      {"SYNAPSE_CONFIG" => "#{File.dirname(__FILE__)}/../../config/discovery-multi.conf.json"})
    stub_const 'ARGV', []

    load "#{File.dirname(__FILE__)}/../../bin/synapse"
  end
end
