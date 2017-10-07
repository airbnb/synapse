require 'spec_helper'
require 'tempfile'

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
end
