require 'spec_helper'
require 'synapse/service_watcher'

describe Synapse::ServiceWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end
  subject { Synapse::ServiceWatcher }
  let(:config) do
    {
      'haproxy' => {
        'port' => '8080',
        'server_port_override' => '8081',
      },
      'discovery' => discovery_config,
    }
  end

  let(:discovery_config) do
    {}
  end

  context 'bogus arguments' do
    let(:discovery_config) {{'method' => 'bogus'}}

    it 'complains if discovery method is bogus' do
      expect {
        subject.create('test', config, mock_synapse)
      }.to raise_error(ArgumentError)
    end
  end

  context 'service watcher dispatch' do
    subject {
      Synapse::ServiceWatcher.create('test', config, mock_synapse)
    }
    
    context 'with method => base' do
      let(:discovery_config) {
        {
          'method' => 'base',
        }
      }

      it 'creates watcher correctly' do
        expect(Synapse::ServiceWatcher::BaseWatcher).to receive(:new).exactly(:once).with(config, nil, mock_synapse)
        expect { subject }.not_to raise_error
      end

      it 'passes custom callback' do
        cb = lambda { }
        expect(cb).to receive(:call).exactly(:once)

        watcher = Synapse::ServiceWatcher.create('test', config, cb, mock_synapse)
        watcher.send(:reconfigure!)
      end
    end

    context 'with method => zookeeper' do
      let(:discovery_config) {
        {
          'method' => 'zookeeper',
          'hosts' => 'localhost:2181',
          'path' => '/smartstack',
        }
      }

      it 'creates watcher correctly' do
        expect(Synapse::ServiceWatcher::ZookeeperWatcher).to receive(:new).exactly(:once).with(config, nil, mock_synapse)
        expect { subject }.not_to raise_error
      end
    end

    context 'with method => dns' do
      let(:discovery_config) {
        {
          'method' => 'dns',
          'servers' => ['localhost'],
        }
      }

      it 'creates watcher correctly' do
        expect(Synapse::ServiceWatcher::DnsWatcher).to receive(:new).exactly(:once).with(config, nil, mock_synapse)
        expect{ subject }.not_to raise_error
      end
    end

    context 'with method => docker' do
      let(:discovery_config) {
        {
          'method' => 'docker',
          'servers' => 'localhost',
          'image_name' => 'servicefoo',
          'container_port' => 1234,
        }
      }

      it 'creates watcher correctly' do
        expect(Synapse::ServiceWatcher::DockerWatcher).to receive(:new).exactly(:once).with(config, nil, mock_synapse)
        expect{ subject }.not_to raise_error
      end
    end

    context 'with method => ec2tag' do
      let(:discovery_config) {
        {
          'method' => 'ec2tag',
          'tag_name' => 'footag',
          'tag_value' => 'barvalue',
          'aws_access_key_id' => 'bogus',
          'aws_secret_access_key' => 'morebogus',
          'aws_region' => 'evenmorebogus',
        }
      }

      it 'creates watcher correctly' do
        expect(Synapse::ServiceWatcher::Ec2tagWatcher).to receive(:new).exactly(:once).with(config, nil, mock_synapse)
        expect{ subject }.not_to raise_error
      end
    end

    context 'with method => zookeeper_dns' do
      let(:discovery_config) {
        {
          'method' => 'zookeeper_dns',
          'hosts' => 'localhost:2181',
          'path' => '/smartstack',
        }
      }

      it 'creates watcher correctly' do
        expect(Synapse::ServiceWatcher::ZookeeperDnsWatcher).to receive(:new).exactly(:once).with(config, nil, mock_synapse)
        expect{ subject }.not_to raise_error
      end
    end

    context 'with method => marathon' do
      let(:discovery_config) {
        {
          'method' => 'marathon',
          'marathon_api_url' => 'localhost:12345',
          'application_name' => 'foobar',
        }
      }

      it 'creates watcher correctly' do
        expect(Synapse::ServiceWatcher::MarathonWatcher).to receive(:new).exactly(:once).with(config, nil, mock_synapse)
        expect{ subject }.not_to raise_error
      end
    end
  end

end


