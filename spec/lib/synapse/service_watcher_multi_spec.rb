require 'spec_helper'
require 'synapse/service_watcher/multi'
require 'synapse/service_watcher/zookeeper'
require 'synapse/service_watcher/dns'

describe Synapse::ServiceWatcher::MultiWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end

  subject {
    Synapse::ServiceWatcher::MultiWatcher.new(config, mock_synapse)
  }

  let(:discovery) do
    valid_discovery
  end

  let (:zk_discovery) do
    {'method' => 'zookeeper', 'hosts' => 'localhost:2181', 'path' => '/smartstack'}
  end

  let (:dns_discovery) do
    {'method' => 'dns', 'servers' => ['localhost']}
  end

  let(:valid_discovery) do
    {'method' => 'multi', 'watchers' => {
       'primary' => zk_discovery,
       'secondary' => dns_discovery,
     }}
  end

  let(:config) do
    {
      'name' => 'test',
      'haproxy' => {},
      'discovery' => discovery,
    }
  end

  describe '.initialize' do
    subject {
      Synapse::ServiceWatcher::MultiWatcher
    }

    context 'with empty configuration' do
      let(:discovery) do
        {}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with empty watcher configuration' do
      let(:discovery) do
        {'method' => 'multi', 'watchers' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with wrong method type' do
      let(:discovery) do
        {'method' => 'zookeeper', 'watchers' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with valid configuration' do
      let(:discovery) do
        valid_discovery
      end

      it 'creates the requested watchers' do
        expect(Synapse::ServiceWatcher::ZookeeperWatcher)
          .to receive(:new)
          .with({'name' => 'test', 'haproxy' => {}, 'discovery' => zk_discovery}, mock_synapse)
          .and_call_original
        expect(Synapse::ServiceWatcher::DnsWatcher)
          .to receive(:new)
          .with({'name' => 'test', 'haproxy' => {}, 'discovery' => dns_discovery}, mock_synapse)
          .and_call_original

        expect {
          subject.new(config, mock_synapse)
        }.not_to raise_error
      end

      it 'has sets @watchers to each watcher' do
        multi_watcher = subject.new(config, mock_synapse)
        watchers = multi_watcher.instance_variable_get(:@watchers)

        expect(watchers.has_key?('primary'))
        expect(watchers.has_key?('secondary'))

        expect(watchers['primary']).to be_instance_of(Synapse::ServiceWatcher::ZookeeperWatcher)
        expect(watchers['secondary']).to be_instance_of(Synapse::ServiceWatcher::DnsWatcher)
      end
    end
  end

  describe '.start' do
    it 'starts all child watchers' do
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        expect(w).to receive(:start)
      end

      expect {
        subject.start
      }.not_to raise_error
    end
  end

  describe '.stop' do
    it 'stops all child watchers' do
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        expect(w).to receive(:stop)
      end

      expect {
        subject.stop
      }.not_to raise_error
    end
  end

  describe ".ping?" do
    it 'calls ping? on all watchers' do
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        expect(w).to receive(:ping?)
      end

      expect {
        subject.ping?
      }.not_to raise_error
    end
  end
end
