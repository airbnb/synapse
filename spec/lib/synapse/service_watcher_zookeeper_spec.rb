require 'spec_helper'
require 'synapse/service_watcher/zookeeper'
require 'synapse/service_watcher/zookeeper_dns'

describe Synapse::ServiceWatcher::ZookeeperWatcher do
  let(:mock_synapse) { double }
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
    let(:discovery) { { 'method' => 'zookeeper', 'hosts' => 'somehost','path' => 'some/path' } }
    subject { Synapse::ServiceWatcher::ZookeeperWatcher.new(config, mock_synapse) }
    it 'decodes data correctly' do
      expect(subject.send(:deserialize_service_instance, service_data_string)).to eql(deserialized_service_data)
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
