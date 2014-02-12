require 'spec_helper'

class Synapse::DockerWatcher
  attr_reader :check_interval, :watcher, :synapse
  attr_accessor :default_servers
end

describe Synapse::DockerWatcher do
  let(:mocksynapse) { double() }
  subject { Synapse::DockerWatcher.new(testargs, mocksynapse) }
  let(:testargs) { { 'name' => 'foo', 'discovery' => { 'method' => 'docker', 'servers' => [{'host' => 'server1.local', 'name' => 'mainserver'}], 'image_name' => 'mycool/image', 'container_port' => 6379 }, 'haproxy' => {} }}
  before(:each) do
    allow(subject.log).to receive(:warn)
    allow(subject.log).to receive(:info)
  end

  def add_arg(name, value)
    args = testargs.clone
    args['discovery'][name] = value
    args
  end

  context "can construct normally" do
    it('can at least construct') { expect { subject }.not_to raise_error }
  end

  context "normal tests" do
    it('starts a watcher thread') do
      watcher_mock = double()
      expect(Thread).to receive(:new).and_return(watcher_mock)
      subject.start
      expect(subject.watcher).to equal(watcher_mock)
    end
    it('sets default check interval') do
      expect(Thread).to receive(:new).and_return(double)
      subject.start
      expect(subject.check_interval).to eq(15.0)
    end
  end

  context "watch tests" do
    before(:each) do
      expect(subject).to receive(:sleep_until_next_check) do |arg|
        subject.instance_variable_set('@should_exit', true)
      end
    end
    it('has a happy first run path, configuring backends') do
      expect(subject).to receive(:containers).and_return(['container1'])
      expect(subject).to receive(:configure_backends).with(['container1'])
      subject.send(:watch)
    end
    it('does not call configure_backends if there is no change') do
      expect(subject).to receive(:containers).and_return([])
      expect(subject).to_not receive(:configure_backends)
      subject.send(:watch)
    end
  end
  context "watch eats exceptions" do
    it "blows up when finding containers" do
      expect(subject).to receive(:containers) do |arg|
        subject.instance_variable_set('@should_exit', true)
        raise('throw exception inside watch')
      end
      expect { subject.send(:watch) }.not_to raise_error
    end
  end

  context "configure_backends tests" do
    before(:each) do
      expect(subject.synapse).to receive(:'reconfigure!').at_least(:once)
    end
    it 'runs' do
      expect { subject.send(:configure_backends, []) }.not_to raise_error
    end
    it 'sets backends right' do
      subject.send(:configure_backends, ['foo'])
      expect(subject.backends).to eq(['foo'])
    end
    it 'resets to default backends if no container found' do
      subject.default_servers = ['fallback1']
      subject.send(:configure_backends, ['foo'])
      expect(subject.backends).to eq(['foo'])
      subject.send(:configure_backends, [])
      expect(subject.backends).to eq(['fallback1'])
    end
    it 'does not reset to default backends if there are no default backends' do
      subject.default_servers = []
      subject.send(:configure_backends, ['foo'])
      expect(subject.backends).to eq(['foo'])
      subject.send(:configure_backends, [])
      expect(subject.backends).to eq(['foo'])
    end
  end

  context "rewrite_container_ports tests" do
    it 'doesnt break if Ports => nil' do
        subject.send(:rewrite_container_ports, nil)
    end
    it 'works for old style port mappings' do
      expect(subject.send(:rewrite_container_ports, "0.0.0.0:49153->6379/tcp, 0.0.0.0:49154->6390/tcp")).to \
        eql({'6379' => '49153', '6390' => '49154'})
    end
    it 'works for new style port mappings' do
      expect(subject.send(:rewrite_container_ports, [{'PrivatePort' => 6379, 'PublicPort' => 49153}, {'PublicPort' => 49154, 'PrivatePort' => 6390}])).to \
        eql({'6379' => '49153', '6390' => '49154'})
    end
  end

  context "container discovery tests" do
    before(:each) do
      getter = double()
      expect(getter).to receive(:get)
      expect(Docker).to receive(:connection).and_return(getter)
    end

    it('has a sane uri') { subject.send(:containers); expect(Docker.url).to eql('http://server1.local:4243') }

    context 'old style port mappings' do
      context 'works for one container' do
        let(:docker_data) { [{"Ports" => "0.0.0.0:49153->6379/tcp, 0.0.0.0:49154->6390/tcp", "Image" => "mycool/image:tagname"}] }
        it do 
          expect(Docker::Util).to receive(:parse_json).and_return(docker_data)
          expect(subject.send(:containers)).to eql([{"name"=>"mainserver", "host"=>"server1.local", "port"=>"49153"}])
         end
      end
      context 'works for multiple containers' do
        let(:docker_data) { [{"Ports" => "0.0.0.0:49153->6379/tcp, 0.0.0.0:49154->6390/tcp", "Image" => "mycool/image:tagname"}, {"Ports" => "0.0.0.0:49155->6379/tcp", "Image" => "mycool/image:tagname"}] }
        it do
          expect(Docker::Util).to receive(:parse_json).and_return(docker_data)
          expect(subject.send(:containers)).to eql([{"name"=>"mainserver", "host"=>"server1.local", "port"=>"49153"},{"name"=>"mainserver", "host"=>"server1.local", "port"=>"49155"}])
        end
      end
    end

    context 'new style port mappings' do
      let(:docker_data) { [{"Ports" => [{'PrivatePort' => 6379, 'PublicPort' => 49153}, {'PublicPort' => 49154, 'PrivatePort' => 6390}], "Image" => "mycool/image:tagname"}] }
      it do
        expect(Docker::Util).to receive(:parse_json).and_return(docker_data)
        expect(subject.send(:containers)).to eql([{"name"=>"mainserver", "host"=>"server1.local", "port"=>"49153"}])
      end
    end

    context 'filters out wrong images' do
      let(:docker_data) { [{"Ports" => "0.0.0.0:49153->6379/tcp, 0.0.0.0:49154->6390/tcp", "Image" => "mycool/image:tagname"}, {"Ports" => "0.0.0.0:49155->6379/tcp", "Image" => "wrong/image:tagname"}] }
      it do
        expect(Docker::Util).to receive(:parse_json).and_return(docker_data)
        expect(subject.send(:containers)).to eql([{"name"=>"mainserver", "host"=>"server1.local", "port"=>"49153"}])
      end
    end
  end
end

