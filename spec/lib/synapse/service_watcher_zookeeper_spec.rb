require 'spec_helper'
require 'synapse/service_watcher/zookeeper'
require 'synapse/service_watcher/zookeeper_dns'

describe Synapse::ServiceWatcher::ZookeeperWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end
  let(:config) do
    {
      'name' => 'test',
      'haproxy' => {},
      'discovery' => discovery,
    }
  end

  let(:service_data) do
    {
      'host' => 'server',
      'port' => '8888',
      'name' => 'server',
      'weight' => '1',
      'haproxy_server_options' => 'backup',
      'labels' => { 'az' => 'us-east-1a' }
    }
  end
  let(:service_data_string) { service_data.to_json }
  let(:deserialized_service_data) {
    [ service_data['host'], service_data['port'], service_data['name'], service_data['weight'],
      service_data['haproxy_server_options'], service_data['labels'] ]
  }

  context 'ZookeeperWatcher' do
    let(:discovery) { { 'method' => 'zookeeper', 'hosts' => 'somehost', 'path' => 'some/path' } }
    let(:mock_zk) { double(ZK) }
    let(:mock_node) do
      node_double = double()
      allow(node_double).to receive(:first).and_return(service_data_string)
      node_double
    end

    subject { Synapse::ServiceWatcher::ZookeeperWatcher.new(config, mock_synapse) }
    it 'decodes data correctly' do
      expect(subject.send(:deserialize_service_instance, service_data_string)).to eql(deserialized_service_data)
    end

    it 'reacts to zk push events' do
      expect(subject).to receive(:watch)
      expect(subject).to receive(:discover).and_call_original
      expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).and_return(
        ["test_child_1"]
      )
      expect(mock_zk).to receive(:get).with('some/path/test_child_1').and_return(mock_node)
      subject.instance_variable_set('@zk', mock_zk)
      expect(subject).to receive(:set_backends).with([service_data.merge({'id' => 1})])
      subject.send(:watcher_callback).call
    end

    it 'handles zk consistency issues' do
      expect(subject).to receive(:watch)
      expect(subject).to receive(:discover).and_call_original
      expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).and_return(
        ["test_child_1"]
      )
      expect(mock_zk).to receive(:get).with('some/path/test_child_1').and_raise(ZK::Exceptions::NoNode)
      subject.instance_variable_set('@zk', mock_zk)
      expect(subject).to receive(:set_backends).with([])
      subject.send(:watcher_callback).call
    end
  end

  context 'ZookeeperDnsWatcher' do
    let(:discovery) { { 'method' => 'zookeeper_dns', 'hosts' => 'somehost','path' => 'some/path' } }
    let(:message_queue) { [] }
    subject { Synapse::ServiceWatcher::ZookeeperDnsWatcher::Zookeeper.new(config, mock_synapse, message_queue) }
    it 'decodes data correctly' do
      expect(subject.send(:deserialize_service_instance, service_data_string)).to eql(deserialized_service_data)
    end
  end
end
