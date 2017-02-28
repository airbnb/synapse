require 'spec_helper'
require 'synapse/service_watcher/ec2tag'
require 'logging'

class Synapse::ServiceWatcher::Ec2tagWatcher
  attr_reader   :synapse
  attr_accessor :default_servers, :ec2
end

class FakeAWSInstance
  def ip_address
    @ip_address ||= fake_address
  end

  def private_ip_address
    @private_ip_address ||= fake_address
  end

  def dns_name
    @dns_name ||= "ec2-#{ip_address.gsub('.', '-')}.eu-test-1.compute.amazonaws.com"
  end

  def private_dns_name
    @private_dns_name ||= "ip-#{private_ip_address.gsub('.', '-')}.eu-test-1.compute.internal"
  end

  def fake_address
    4.times.map { (0...254).to_a.shuffle.pop.to_s }.join('.')
  end
end

describe Synapse::ServiceWatcher::Ec2tagWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    allow(mock_synapse).to receive(:reconfigure!).and_return(true)
    mock_synapse
  end
  subject { Synapse::ServiceWatcher::Ec2tagWatcher.new(basic_config, mock_synapse) }

  let(:basic_config) do
    { 'name' => 'ec2tagtest',
      'haproxy' => {
        'port' => '8080',
        'server_port_override' => '8081'
      },
      "discovery" => {
        "method" => "ec2tag",
        "tag_name"   => "fuNNy_tag_name",
        "tag_value"  => "funkyTagValue",
        "aws_region" => 'eu-test-1',
        "aws_access_key_id" => 'ABCDEFGHIJKLMNOPQRSTU',
        "aws_secret_access_key" => 'verylongfakekeythatireallyneedtogenerate'
      }
    }
  end

  before(:all) do
    # Clean up ENV so we don't inherit any actual AWS config.
    %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION].each { |k| ENV.delete(k) }
  end

  before(:each) do
    # https://ruby.awsblog.com/post/Tx2SU6TYJWQQLC3/Stubbing-AWS-Responses
    # always returns empty results, so data may have to be faked.
    AWS.stub!
  end

  def remove_discovery_arg(name)
    args = basic_config.clone
    args['discovery'].delete name
    args
  end

  def remove_haproxy_arg(name)
    args = basic_config.clone
    args['haproxy'].delete name
    args
  end

  def munge_haproxy_arg(name, new_value)
    args = basic_config.clone
    args['haproxy'][name] = new_value
    args
  end

  def munge_arg(name, new_value)
    args = basic_config.clone
    args[name] = new_value
    args
  end

  describe '#new' do
    let(:args) { basic_config }

    it 'instantiates cleanly with basic config' do
      expect { subject }.not_to raise_error
    end

    context 'when missing arguments' do
      it 'does not break if aws_region is missing' do
        expect {
          Synapse::ServiceWatcher::Ec2tagWatcher.new(remove_discovery_arg('aws_region'), mock_synapse)
        }.not_to raise_error
      end
      it 'does not break if aws_access_key_id is missing' do
        expect {
          Synapse::ServiceWatcher::Ec2tagWatcher.new(remove_discovery_arg('aws_access_key_id'), mock_synapse)
        }.not_to raise_error
      end
      it 'does not break if aws_secret_access_key is missing' do
        expect {
          Synapse::ServiceWatcher::Ec2tagWatcher.new(remove_discovery_arg('aws_secret_access_key'), mock_synapse)
        }.not_to raise_error
      end
      it 'complains if server_port_override and backend_port_override are missing' do
        expect {
          Synapse::ServiceWatcher::Ec2tagWatcher.new(remove_haproxy_arg('server_port_override'), mock_synapse)
        }.to raise_error(ArgumentError, /Missing backend_port_override/)
      end
      it 'does not break if backend_port_override is set' do
        expect {
          Synapse::ServiceWatcher::Ec2tagWatcher.new(munge_arg('backend_port_override', 1234), mock_synapse)
        }.not_to raise_error
      end
    end

    context 'invalid data' do
      it 'complains if the haproxy server_port_override is not a number' do
        expect {
          Synapse::ServiceWatcher::Ec2tagWatcher.new(munge_haproxy_arg('server_port_override', '80deadbeef'), mock_synapse)
        }.to raise_error(ArgumentError, /Invalid backend_port_override/)
      end
      it 'complains if the backend_port_override is not a number' do
        config = remove_haproxy_arg('server_port_override')
        expect(config['haproxy']['backend_port_override']).to eq(nil)
        config = munge_arg('backend_port_override', '80deadbeef')
        expect {
          Synapse::ServiceWatcher::Ec2tagWatcher.new(config, mock_synapse)
        }.to raise_error(ArgumentError, /Invalid backend_port_override/)
      end

    end
  end

  context "instance discovery" do
    let(:instance1) { FakeAWSInstance.new }
    let(:instance2) { FakeAWSInstance.new }

    context 'watch' do

      it 'discovers instances, configures backends, then sleeps' do
        fake_backends = [1,2,3]
        expect(subject).to receive(:discover_instances).and_return(fake_backends)
        expect(subject).to receive(:set_backends).with(fake_backends) { subject.stop }
        expect(subject).to receive(:sleep_until_next_check)
        subject.send(:watch)
      end

      it 'sleeps until next check if discover_instances fails' do
        expect(subject).to receive(:discover_instances) do
          subject.stop
          raise "discover failed"
        end
        expect(subject).to receive(:sleep_until_next_check)
        subject.send(:watch)
      end

    end

    context 'using the AWS API' do
      let(:ec2_client) { double('AWS::EC2') }
      let(:instance_collection) { double('AWS::EC2::InstanceCollection') }

      before do
        subject.ec2 = ec2_client
      end

      it 'fetches instances and filter instances' do
        # Unfortunately there's quite a bit going on here, but this is
        # a chained call to get then filter EC2 instances, which is
        # done remotely; breaking into separate calls would result in
        # unnecessary data being retrieved.

        expect(subject.ec2).to receive(:instances).and_return(instance_collection)

        expect(instance_collection).to receive(:tagged).with('foo').and_return(instance_collection)
        expect(instance_collection).to receive(:tagged_values).with('bar').and_return(instance_collection)
        expect(instance_collection).to receive(:select).and_return(instance_collection)

        subject.send(:instances_with_tags, 'foo', 'bar')
      end
    end

    context 'returned backend data structure' do
      before do
        allow(subject).to receive(:instances_with_tags).and_return([instance1, instance2])
      end

      let(:backends) { subject.send(:discover_instances) }

      it 'returns an Array of backend name/host/port Hashes' do
        required_keys = %w[name host port]
        expect(
          backends.all?{|b| required_keys.each{|k| b.has_key?(k)}}
        ).to be_truthy
      end

      it 'sets the backend port to server_port_override for all backends' do
        discovered_backends = subject.send(:discover_instances)
        expect(
          discovered_backends.all? { |b| b['port'].nil? }
        ).to be_truthy

        # Set backends is responsible for actually populating ports
        expect(subject.send(:set_backends, discovered_backends)).to eq(true)
        expect(
          subject.backends.all? { |b| b['port'] == basic_config['haproxy']['server_port_override'] }
        ).to be_truthy
      end
    end

    context 'returned instance fields' do
      before do
        allow(subject).to receive(:instances_with_tags).and_return([instance1])
      end

      let(:backend) { subject.send(:discover_instances).pop }

      it "returns an instance's private IP as the hostname" do
        expect( backend['host'] ).to eq instance1.private_ip_address
      end

      it "returns an instance's private hostname as the server name" do
        expect( backend['name'] ).to eq instance1.private_dns_name
      end
    end
  end
end

