require 'spec_helper'
require 'synapse/service_watcher/dns'

describe Synapse::ServiceWatcher::DnsWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end

  let(:discovery) do
    {
      'method' => 'dns',
      'servers' => servers,
      'generator_config_path' => 'disabled',
    }
  end

  let(:config) do
    {
      'name' => 'test',
      'haproxy' => {},
      'discovery' => discovery,
    }
  end

  let (:servers) do
    [
      {'name' => 'test1', 'host' => 'localhost'},
      {'name' => 'test2', 'host' => '127.0.0.1'},
      {'name' => 'test3', 'host' => '::1'},
    ]
  end

  subject { Synapse::ServiceWatcher::DnsWatcher.new(config, mock_synapse) }

  it 'only resolves hostnames' do
    resolver = instance_double("Resolv::DNS")
    allow(subject).to receive(:resolver).and_return(resolver)
    expect(resolver).to receive(:getaddresses).with('localhost').
      and_return([Resolv::IPv4.create('127.0.0.2')])
    expect(subject.send(:resolve_servers)).to eql([
      [{'name' => 'test1', 'host' => 'localhost'}, ['127.0.0.2']],
      [{'name' => 'test2', 'host' => '127.0.0.1'}, ['127.0.0.1']],
      [{'name' => 'test3', 'host' => '::1'}, ['::1']],
    ])
  end
end
