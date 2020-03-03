require 'spec_helper'
require 'synapse'
require 'synapse/service_watcher/base'

describe Synapse do
  let(:discovery) {
    {
       "method" => "base"
    }
  }

  let(:local_haproxy) {
    {
       "port" => 3213,
       "server_options" => "check inter 2s rise 3 fall 2",
       "bind_options" => "",
       "listen" => [
         "mode http",
         "option httpcheck /health",
         "http-check expect string OK"
       ]
     }
  }

  let(:service) {
    {"discovery" => discovery, "haproxy" => local_haproxy}
  }

  let(:global_haproxy) {
    {
      "global" => [
        "daemon",
        "maxconn 4096",
      ],
      "defaults" => [],
      "do_writes" => false,
      "do_socket" => false,
      "do_checks" => false,
      "do_reloads" => false,
    }
  }

  let(:config) {
    {"services" => {
       "service1" => service,
     },
     "haproxy" => global_haproxy,
     }
  }

  subject {
    Synapse::Synapse.new(config)
  }

  describe "#initialize" do
    it 'creates watchers' do
      expect(Synapse::ServiceWatcher::BaseWatcher)
        .to receive(:new)
        .exactly(:once)
        .with(service, an_instance_of(Synapse::Synapse), duck_type(:call))

      expect { subject }.not_to raise_error
    end

    it 'passes watchers proper reconfigure callback' do
      expect(subject).to receive(:reconfigure!).exactly(:once)

      watchers = subject.instance_variable_get(:@service_watchers)
      expect(watchers.length).to eq(1)

      watchers[0].send(:reconfigure!)
    end
  end
end
