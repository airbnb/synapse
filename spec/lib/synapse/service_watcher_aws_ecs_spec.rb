require 'spec_helper'

describe Synapse::AwsEcsWatcher do
  let(:mock_synapse) { double }
  subject { Synapse::AwsEcsWatcher.new(args, mock_synapse) }
  
  let(:basic_args) do
    { 'name' => 'foo', 
      'discovery' => {
        'method' => 'aws_ecs',
	'aws_region' => 'us-east-1',
	'aws_ecs_cluster' => 'default',
	'aws_ecs_family' => 'helloworld',
	'aws_access_key_id' => 'AFAKEKEY',
	'aws_secret_access_key' => 'AREALLYFAKEACCESSKEY'
      },
      'haproxy' => {
        'port' => '8000'
      }
    }
  end

  def remove_discovery_arg(name)
    args = basic_args.clone
    args['discovery'].delete name
    args
  end

  describe '#new' do
    let(:args) { basic_args }
    it('can at least construct') { expect { subject }.not_to raise_error }
    context 'when missing args' do
      it('fails with no cluster') do
        expect { Synapse::AwsEcsWatcher.new(remove_discovery_arg('aws_ecs_cluster'), mock_synapse) }.to raise_error(ArgumentError, /aws_ecs_cluster/)
      end
      
      it('fails with no family') do
        expect { Synapse::AwsEcsWatcher.new(remove_discovery_arg('aws_ecs_family'), mock_synapse) }.to raise_error(ArgumentError, /aws_ecs_family/)
      end
    end
  end

  context 'task discovery' do
    let(:args) { basic_args }
    let(:task_1) { double }
    let(:task_2) { double }
    let(:ci_1) { double }
    let(:ci_2) { double }
    let(:ec2_list_1) { double }
    let(:ec2_list_2) { double }
    let(:instance_1) { double }
    let(:instance_2) { double }
    let(:container_1) { double }
    let(:container_2) { double }
    let(:nb_1) { double }
    let(:nb_2) { double }
    it 'properly discovers a single task' do
      subject.should_receive(:api_task_ids).and_return([['t_id1']])
      subject.should_receive(:api_describe_tasks).with(['t_id1']).and_return([task_1])
      task_1.should_receive(:container_instance_arn).twice.and_return('ci_id1')
      subject.should_receive(:api_describe_container_instances).with(['ci_id1']).and_return([ci_1])
      ci_1.should_receive(:container_instance_arn).and_return('ci_id1')
      ci_1.should_receive(:ec2_instance_id).twice.and_return('ec2_id1')
      subject.should_receive(:api_describe_instances).with(['ec2_id1']).and_return([ec2_list_1])
      ec2_list_1.should_receive(:instances).and_return([instance_1])
      instance_1.should_receive(:instance_id).and_return('ec2_id1')
      task_1.should_receive(:last_status).and_return("RUNNING")
      task_1.should_receive(:containers).and_return([container_1])
      container_1.should_receive(:network_bindings).twice.and_return([nb_1])
      nb_1.should_receive(:host_port).twice.and_return(80)
      instance_1.should_receive(:private_dns_name).and_return('dns.amazonaws.internal')
      instance_1.should_receive(:private_ip_address).and_return('10.0.0.10')
      expect(subject.discover_tasks).to eq([{'name' => 'dns.amazonaws.internal','host' => '10.0.0.10', 'port' => 80}])
    end

    it 'does not discover an ambiguous task' do
      subject.should_receive(:api_task_ids).and_return([['t_id1']])
      subject.should_receive(:api_describe_tasks).with(['t_id1']).and_return([task_1])
      task_1.should_receive(:container_instance_arn).and_return('ci_id1')
      subject.should_receive(:api_describe_container_instances).with(['ci_id1']).and_return([ci_1])
      ci_1.should_receive(:container_instance_arn).and_return('ci_id1')
      ci_1.should_receive(:ec2_instance_id).and_return('ec2_id1')
      subject.should_receive(:api_describe_instances).with(['ec2_id1']).and_return([ec2_list_1])
      ec2_list_1.should_receive(:instances).and_return([instance_1])
      instance_1.should_receive(:instance_id).and_return('ec2_id1')
      task_1.should_receive(:last_status).and_return("RUNNING")
      task_1.should_receive(:containers).and_return([container_1])
      container_1.should_receive(:network_bindings).twice.and_return([nb_1, nb_2])
      nb_1.should_receive(:host_port).twice.and_return(80)
      nb_2.should_receive(:host_port).twice.and_return(8080)
      expect(subject.discover_tasks).to eq([])
    end

    it 'properly discovers multiple tasks' do
      subject.should_receive(:api_task_ids).and_return([['t_id1', 't_id2']])
      subject.should_receive(:api_describe_tasks).with(['t_id1', 't_id2']).and_return([task_1, task_2])
      task_1.should_receive(:container_instance_arn).twice.and_return('ci_id1')
      task_2.should_receive(:container_instance_arn).twice.and_return('ci_id2')
      subject.should_receive(:api_describe_container_instances).with(['ci_id1', 'ci_id2']).and_return([ci_1, ci_2])
      ci_1.should_receive(:container_instance_arn).and_return('ci_id1')
      ci_1.should_receive(:ec2_instance_id).twice.and_return('ec2_id1')
      ci_2.should_receive(:container_instance_arn).and_return('ci_id2')
      ci_2.should_receive(:ec2_instance_id).twice.and_return('ec2_id2')
      subject.should_receive(:api_describe_instances).with(['ec2_id1', 'ec2_id2']).and_return([ec2_list_1, ec2_list_2])
      ec2_list_1.should_receive(:instances).and_return([instance_1])
      ec2_list_2.should_receive(:instances).and_return([instance_2])
      instance_1.should_receive(:instance_id).and_return('ec2_id1')
      instance_2.should_receive(:instance_id).and_return('ec2_id2')
      task_1.should_receive(:last_status).and_return("RUNNING")
      task_1.should_receive(:containers).and_return([container_1])
      task_2.should_receive(:last_status).and_return("RUNNING")
      task_2.should_receive(:containers).and_return([container_2])
      container_1.should_receive(:network_bindings).twice.and_return([nb_1])
      container_2.should_receive(:network_bindings).twice.and_return([nb_2])
      nb_1.should_receive(:host_port).twice.and_return(80)
      nb_2.should_receive(:host_port).twice.and_return(8080)
      instance_1.should_receive(:private_dns_name).and_return('dns.amazonaws.internal')
      instance_1.should_receive(:private_ip_address).and_return('10.0.0.1')
      instance_2.should_receive(:private_dns_name).and_return('dns2.amazonaws.internal')
      instance_2.should_receive(:private_ip_address).and_return('10.0.0.2')
      expect(subject.discover_tasks).to eq([{'name' => 'dns.amazonaws.internal','host' => '10.0.0.1', 'port' => 80},
        {'name' => 'dns2.amazonaws.internal','host' => '10.0.0.2', 'port' => 8080}])
    end

  end
end
