require 'spec_helper'
require 'synapse/service_watcher/multi/multi'
require 'synapse/service_watcher/zookeeper/zookeeper'
require 'synapse/service_watcher/dns/dns'
require 'synapse/service_watcher/multi/resolver/base'

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
    Synapse::ServiceWatcher::MultiWatcher.new(config, mock_synapse, reconfigure_callback)
  }

  let(:reconfigure_callback) { -> {} }

  let(:discovery) do
    valid_discovery
  end

  let (:zk_discovery) do
    {'method' => 'zookeeper', 'hosts' => ['localhost:2181'], 'path' => '/smartstack'}
  end

  let (:dns_discovery) do
    {'method' => 'dns', 'servers' => ['localhost']}
  end

  let(:valid_discovery) do
    {'method' => 'multi',
     'watchers' => {
       'primary' => zk_discovery,
       'secondary' => dns_discovery,
     },
     'resolver' => {
       'method' => 'base',
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
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with empty watcher configuration' do
      let(:discovery) do
        {'method' => 'multi', 'watchers' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with undefined watchers' do
      let(:discovery) do
        {'method' => 'muli'}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with wrong method type' do
      let(:discovery) do
        {'method' => 'zookeeper', 'watchers' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with invalid child watcher definition' do
      let(:discovery) {
        {'method' => 'multi', 'watchers' => {
           'secondary' => {
             'method' => 'bogus',
           }
         }}
      }

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with invalid child watcher type' do
      let(:discovery) {
        {'method' => 'multi', 'watchers' => {
           'child' => 'not_a_hash'
         }}
      }

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with undefined resolver' do
      let(:discovery) do
        {'method' => 'multi', 'watchers' => {
           'child' => zk_discovery
         }}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with empty resolver' do
      let(:discovery) do
        {'method' => 'multi', 'watchers' => {
           'child' => zk_discovery
         },
        'resolver' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
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
          .with({'name' => 'test', 'haproxy' => {}, 'discovery' => zk_discovery}, mock_synapse, duck_type(:call))
          .and_call_original
        expect(Synapse::ServiceWatcher::DnsWatcher)
          .to receive(:new)
          .with({'name' => 'test', 'haproxy' => {}, 'discovery' => dns_discovery}, mock_synapse, duck_type(:call))
          .and_call_original

        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.not_to raise_error
      end

      it 'creates the requested resolver' do
        expect(Synapse::ServiceWatcher::Resolver::BaseResolver)
          .to receive(:new)
          .with({'method' => 'base'},
                [ instance_of(Synapse::ServiceWatcher::ZookeeperWatcher),
                  instance_of(Synapse::ServiceWatcher::DnsWatcher)])
          .and_call_original

        expect { subject.new(config, mock_synapse) }.not_to raise_error
      end

      it 'sets @watchers to each watcher' do
        multi_watcher = subject.new(config, mock_synapse, reconfigure_callback)
        watchers = multi_watcher.instance_variable_get(:@watchers)

        expect(watchers.has_key?('primary'))
        expect(watchers.has_key?('secondary'))

        expect(watchers['primary']).to be_instance_of(Synapse::ServiceWatcher::ZookeeperWatcher)
        expect(watchers['secondary']).to be_instance_of(Synapse::ServiceWatcher::DnsWatcher)
      end

      it 'sets @resolver to the requested resolver type' do
        watcher = subject.new(config, mock_synapse)
        resolver = watcher.instance_variable_get(:@resolver)

        expect(resolver).to be_instance_of(Synapse::ServiceWatcher::Resolver::BaseResolver)
      end
    end
  end

  describe '.start' do
    it 'starts all child watchers' do
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        expect(w).to receive(:start)
      end

      expect { subject.start }.not_to raise_error
    end

    it 'starts resolver' do
      resolver = subject.instance_variable_get(:@resolver)
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        allow(w).to receive(:start)
      end

      expect(resolver).to receive(:start)
      expect { subject.start }.not_to raise_error
    end
  end

  describe '.stop' do
    it 'stops all child watchers' do
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        expect(w).to receive(:stop)
      end

      expect { subject.stop }.not_to raise_error
    end

    it 'stops resolver' do
      resolver = subject.instance_variable_get(:@resolver)
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        allow(w).to receive(:stop)
      end

      expect(resolver).to receive(:stop)
      expect { subject.stop }.not_to raise_error
    end
  end

  describe ".ping?" do
    context 'when resolver returns false' do
      it 'returns false' do
        resolver = subject.instance_variable_get(:@resolver)
        allow(resolver).to receive(:ping?).and_return(false)

        expect(subject.ping?).to eq(false)
      end
    end

    context 'when resolver returns true' do
      it 'returns true' do
        resolver = subject.instance_variable_get(:@resolver)
        allow(resolver).to receive(:ping?).and_return(true)

        expect(subject.ping?).to eq(true)
      end
    end
  end
end
