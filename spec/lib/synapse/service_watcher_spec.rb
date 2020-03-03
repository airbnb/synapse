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

  context 'with bogus method' do
    let(:discovery_config) {{'method' => 'bogus'}}

    it 'raises an error' do
      expect {
        subject.create('test', config, mock_synapse, -> {})
      }.to raise_error(ArgumentError)
    end
  end

  context 'without reconfigure callback' do
    it 'raises an error' do
      expect {
        subject.create('test', config, mock_synapse)
      }.to raise_error(ArgumentError)
    end
  end

  context 'service watcher dispatch' do
    let(:default_callback) {
      -> {}
    }

    subject {
      Synapse::ServiceWatcher.create('test', config, mock_synapse, default_callback)
    }

    context 'with method => base' do
      let(:discovery_config) {
        {
          'method' => 'base',
        }
      }

      it 'creates watcher correctly' do
        expect(Synapse::ServiceWatcher::BaseWatcher).to receive(:new).exactly(:once).with(config, mock_synapse, default_callback)
        expect { subject }.not_to raise_error
      end

      it 'passes custom callback' do
        cb = -> { }
        expect(cb).to receive(:call).exactly(:once)

        watcher = Synapse::ServiceWatcher.create('test', config, mock_synapse, cb)
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
        expect(Synapse::ServiceWatcher::ZookeeperWatcher).to receive(:new).exactly(:once).with(config, mock_synapse, default_callback)
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
        expect(Synapse::ServiceWatcher::DnsWatcher).to receive(:new).exactly(:once).with(config, mock_synapse, default_callback)
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
        expect(Synapse::ServiceWatcher::DockerWatcher).to receive(:new).exactly(:once).with(config, mock_synapse, default_callback)
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
        expect(Synapse::ServiceWatcher::Ec2tagWatcher).to receive(:new).exactly(:once).with(config, mock_synapse, default_callback)
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
        expect(Synapse::ServiceWatcher::ZookeeperDnsWatcher).to receive(:new).exactly(:once).with(config, mock_synapse, default_callback)
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
        expect(Synapse::ServiceWatcher::MarathonWatcher).to receive(:new).exactly(:once).with(config, mock_synapse, default_callback)
        expect{ subject }.not_to raise_error
      end
    end

    context 'with method => multi' do
      let(:discovery_config) {
        {
          'method' => 'multi',
          'watchers' => {'primary' => {
                           'method' => 'zookeeper',
                           'hosts' => 'localhost:2181',
                           'path' => '/smartstack',
                         },
                         'secondary' => {
                           'method' => 'ec2tag',
                           'tag_name' => 'footag',
                           'tag_value' => 'barvalue',
                           'aws_access_key_id' => 'bogus',
                           'aws_secret_access_key' => 'morebogus',
                           'aws_region' => 'evenmorebogus',
                         }},
          'resolver' => {
            'method' => 'fallback',
          }
        }
      }

      it 'creates watcher correctly' do
        expect(Synapse::ServiceWatcher::MultiWatcher).to receive(:new).exactly(:once).with(config, mock_synapse, default_callback)
        expect{ subject }.not_to raise_error
      end
    end

    context 'with discovery_multi present' do
      let(:discovery) {
        {
          'method' => 'zookeeper',
          'hosts' => 'localhost:2181',
          'path' => '/smartstack',
        }
      }
      let(:watchers) {
        {
          'secondary' => {
            'method' => 'ec2tag',
            'tag_name' => 'footag',
            'tag_value' => 'barvalue',
            'aws_access_key_id' => 'bogus',
            'aws_secret_access_key' => 'morebogus',
            'aws_region' => 'evenmorebogus',
          }}
      }

      let(:discovery_multi) {
        {
          'watchers' => watchers,
          'resolver' => {
            'method' => 'fallback',
          }
        }
      }

      let(:config) {
        {
          'haproxy' => {
            'port' => '8080',
            'server_port_override' => '8081',
          },
          'discovery' => discovery,
          'discovery_multi' => discovery_multi,
        }
      }

      let(:expected_config) {
        expected_config = Marshal.load(Marshal.dump(config))
        expected_config['name'] = 'test'
        expected_config['discovery'] = Marshal.load(Marshal.dump(discovery_multi))
        expected_config['discovery']['watchers']['primary'] = discovery
        expected_config['discovery']['method'] = 'multi'
        expected_config.delete('discovery_multi')

        expected_config
      }

      it 'creates watcher correctly' do
        expect(Synapse::ServiceWatcher::MultiWatcher).to receive(:new).exactly(:once).with(expected_config, mock_synapse, default_callback)
        expect{ subject }.not_to raise_error
      end

      context 'with method already set' do
        let(:multi_method) { 'multi' }

        let(:discovery_multi) {
          {
            'method' => multi_method,
            'watchers' => watchers,
            'resolver' => {
              'method' => 'fallback',
            }
          }
        }

        context 'to not multi' do
          let(:multi_method) { 'bogus' }

          it 'raises an error' do
            expect{ subject }.to raise_error(ArgumentError)
          end
        end

        context 'to multi' do
          it 'creates watcher properly' do
            expect(Synapse::ServiceWatcher::MultiWatcher).to receive(:new).exactly(:once).with(expected_config, mock_synapse, default_callback)
            expect{ subject }.not_to raise_error
          end
        end
      end

      context 'without any watchers set' do
        let(:watchers) {{}}

        it 'creates watcher properly' do
          expect(Synapse::ServiceWatcher::MultiWatcher).to receive(:new).exactly(:once).with(expected_config, mock_synapse, default_callback)
          expect{ subject }.not_to raise_error
        end
      end

      context 'with discovery nil' do
        let(:discovery) { nil }

        it 'creates watcher properly' do
          expect(Synapse::ServiceWatcher::MultiWatcher).to receive(:new).exactly(:once).with(expected_config, mock_synapse, default_callback)
          expect{ subject }.not_to raise_error
        end
      end

      context 'with primary already set' do
        let(:watchers) {
          {'primary' => discovery}
        }
        it 'raises an error' do
          expect{ subject }.to raise_error(ArgumentError)
        end
      end

      context 'with watchers invalid' do
        let(:watchers) {
          {'secondary' => {'method' => 'bogus'}}
        }

        it 'raises an error' do
          expect{ subject }.to raise_error(ArgumentError)
        end
      end
    end
  end
end

