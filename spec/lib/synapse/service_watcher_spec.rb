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
      'discovery' => {
        'method' => 'test'
      }
    }
  end

  def replace_discovery(new_value)
    args = config.clone
    args['discovery'] = new_value
    args
  end

  context 'bogus arguments' do
    it 'complains if discovery method is bogus' do
      expect {
        subject.create('test', config, mock_synapse)
      }.to raise_error(ArgumentError)
    end
  end

  context 'service watcher dispatch' do
    let (:zookeeper_config) {{
      'method' => 'zookeeper',
      'hosts' => 'localhost:2181',
      'path' => '/smartstack',
    }}
    let (:dns_config) {{
      'method' => 'dns',
      'servers' => ['localhost'],
    }}
    let (:docker_config) {{
      'method' => 'docker',
      'servers' => 'localhost',
      'image_name' => 'servicefoo',
      'container_port' => 1234,
    }}
    let (:ec2_config) {{
      'method' => 'ec2tag',
      'tag_name' => 'footag',
      'tag_value' => 'barvalue',
      'aws_access_key_id' => 'bogus',
      'aws_secret_access_key' => 'morebogus',
      'aws_region' => 'evenmorebogus',
    }}
    let (:zookeeper_dns_config) {{
      'method' => 'zookeeper_dns',
      'hosts' => 'localhost:2181',
      'path' => '/smartstack',
    }}
    let (:marathon_config) {{
      'method' => 'marathon',
      'marathon_api_url' => 'localhost:12345',
      'application_name' => 'foobar',
    }}

    it 'creates zookeeper correctly' do
      expect {
        subject.create('test', replace_discovery(zookeeper_config), mock_synapse)
      }.not_to raise_error
    end
    it 'creates dns correctly' do
      expect {
        subject.create('test', replace_discovery(dns_config), mock_synapse)
      }.not_to raise_error
    end
    it 'creates docker correctly' do
      expect {
        subject.create('test', replace_discovery(docker_config), mock_synapse)
      }.not_to raise_error
    end
    it 'creates ec2tag correctly' do
      expect {
        subject.create('test', replace_discovery(ec2_config), mock_synapse)
      }.not_to raise_error
    end
    it 'creates zookeeper_dns correctly' do
      expect {
        subject.create('test', replace_discovery(zookeeper_dns_config), mock_synapse)
      }.not_to raise_error
    end
    it 'creates marathon correctly' do
      expect {
        subject.create('test', replace_discovery(marathon_config), mock_synapse)
      }.not_to raise_error
    end
  end

end


