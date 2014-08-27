require 'spec_helper'
require 'logging'

class Synapse::MarathonWatcher
  attr_reader   :synapse
  attr_accessor :default_servers, :marathon
end

describe Synapse::MarathonWatcher do
  let(:mock_synapse) { double }
  subject { Synapse::MarathonWatcher.new(basic_config, mock_synapse) }

  let(:basic_config) do
    { 'name' => 'marathontest',
      'haproxy' => {
        'port' => '8080',
        'server_port_override' => '8081'
      },
      "discovery" => {
        "method" => "marathon",
        "hostname" => "marathon-server",
        "app_id" => "app_id",
        "port_index" => "1"
      }
    }
  end

  before(:all) do
    # Clean up ENV so we don't inherit any actual Marathon config.
    %w[MARATHON_HOST].each { |k| ENV.delete(k) }
  end

  def remove_discovery_arg(name)
    args = basic_config.clone
    args['discovery'].delete name
    args
  end

  describe '#new' do
    let(:args) { basic_config }

    it 'instantiates cleanly with basic config' do
      expect { subject }.not_to raise_error
    end

    context 'when missing arguments' do
      it 'complains if hostname is missing' do
        expect {
          Synapse::MarathonWatcher.new(remove_discovery_arg('hostname'), mock_synapse)
        }.to raise_error(ArgumentError, /non-empty hostname/)
      end
      it 'complains if app_id is missing' do
        expect {
          Synapse::MarathonWatcher.new(remove_discovery_arg('app_id'), mock_synapse)
        }.to raise_error(ArgumentError, /non-empty app_id/)
      end
    end

    context 'sane defaults' do
      it 'defaults to port_index 0 if not specified' do
          expect {
            Synapse::MarathonWatcher.new(remove_discovery_arg('port_index'), mock_synapse)
          }.to_not raise_error
      end
    end
  end

  context "instance discovery" do
    let(:instance1) { { "id" => "foo", "host" => "foo.example.com", "ports" => [80, 81, 82] } }
    let(:instance2) { { "id" => "bar", "host" => "bar.example.com", "ports" => [90, 91, 92] } }

    context 'using the Marathon API' do
      let(:marathon_client) { double('Marathon::Client') }
      let(:task_list) { double('Marathon::Maration::Response') }

      before do
        subject.marathon = marathon_client
      end

      it 'fetches tasks' do
        expect(subject.marathon).to receive(:list_tasks).and_return(task_list)
        expect(task_list).to receive(:success?).and_return(true)
        expect(task_list).to receive(:parsed_response).and_return({ 'tasks' => [instance1, instance2] })

        subject.send(:list_app_tasks, 'foo')
      end

      it 'handles client errors' do
        expect(subject.marathon).to receive(:list_tasks).and_return(task_list)
        expect(task_list).to receive(:success?).and_return(false)
        expect(task_list).to receive(:error).and_return({ 'error' => 'message' })

        tasks = subject.send(:list_app_tasks, 'foo')

        expect( tasks ).to be_empty
      end
    end

    context 'returned backend data structure' do
      before do
        allow(subject).to receive(:list_app_tasks).and_return([instance1, instance2])
      end

      let(:backends) { subject.send(:discover_instances) }

      it 'returns an Array of backend name/host/port Hashes' do
        expect(backends.all? {|b| %w[name host port].each {|k| b.has_key?(k) }}).to be true
      end

    end

    context 'returned instance fields' do
      before do
        allow(subject).to receive(:list_app_tasks).and_return([instance1])
      end

      let(:backend) { subject.send(:discover_instances).pop }

      it "returns a task's host as the hostname" do
        expect( backend['host'] ).to eq instance1['host']
      end

      it "returns a task's id as the server name" do
        expect( backend['name'] ).to eq instance1['id']
      end

      it "returns a tasks first port as the server port" do
        expect( backend['port'] ).to eq instance1['ports'][1]
      end
    end
  end

  context "configure_backends tests" do
    let(:backend1) { { 'name' => 'foo',  'host' => 'foo.backend.tld',  'port' => '123' } }
    let(:backend2) { { 'name' => 'bar',  'host' => 'bar.backend.tld',  'port' => '456' } }
    let(:fallback) { { 'name' => 'fall', 'host' => 'fall.backend.tld', 'port' => '789' } }

    before(:each) do
      expect(subject.synapse).to receive(:'reconfigure!').at_least(:once)
    end

    it 'runs' do
      expect { subject.send(:configure_backends, []) }.not_to raise_error
    end

    it 'sets backends correctly' do
      subject.send(:configure_backends, [ backend1, backend2 ])
      expect(subject.backends).to eq([ backend1, backend2 ])
    end

    it 'resets to default backends if no instances are found' do
      subject.default_servers = [ fallback ]
      subject.send(:configure_backends, [ backend1 ])
      expect(subject.backends).to eq([ backend1 ])
      subject.send(:configure_backends, [])
      expect(subject.backends).to eq([ fallback ])
    end

    it 'does not reset to default backends if there are no default backends' do
      subject.default_servers = []
      subject.send(:configure_backends, [ backend1 ])
      expect(subject.backends).to eq([ backend1 ])
      subject.send(:configure_backends, [])
      expect(subject.backends).to eq([ backend1 ])
    end
  end
end

