require 'spec_helper'

class Synapse::BaseWatcher
  attr_reader :should_exit, :default_servers
end

describe Synapse::BaseWatcher do
  let(:mocksynapse) { double() }
  subject { Synapse::BaseWatcher.new(args, mocksynapse) }
  let(:testargs) { { 'name' => 'foo', 'discovery' => { 'method' => 'base' }, 'haproxy' => {} }}

  def remove_arg(name)
    args = testargs.clone
    args.delete name
    args
  end

  context "can construct normally" do
    let(:args) { testargs }
    it('can at least construct') { expect { subject }.not_to raise_error }
  end

  ['name', 'discovery', 'haproxy'].each do |to_remove|
    context "without #{to_remove} argument" do
      let(:args) { remove_arg to_remove }
      it('gots bang') { expect { subject }.to raise_error(ArgumentError, "missing required option #{to_remove}") }
    end
  end

  context "normal tests" do
    let(:args) { testargs }
    it('is running') { expect(subject.should_exit).to equal(false) }
    it('can ping') { expect(subject.ping?).to equal(true) }
    it('can be stopped') do
      subject.stop
      expect(subject.should_exit).to equal(true)
    end
  end

  context 'set_backends test' do
    default_servers = ['default_server_1', 'default_server_2']
    let(:args) { testargs.merge({'default_servers' => default_servers}) }

    it 'sets backends' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
      backends = ['server1', 'server2']
      expect(subject.send(:set_backends, backends)).to equal(true)
      expect(subject.backends).to eq(backends)
    end

    it 'removes duplicate backends' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
      backends = ['server1', 'server2']
      duplicate_backends = backends + backends
      expect(subject.send(:set_backends, duplicate_backends)).to equal(true)
      expect(subject.backends).to eq(backends)
    end

    it 'sets backends to default_servers if no backends discovered' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
      expect(subject.send(:set_backends, [])).to equal(true)
      expect(subject.backends).to eq(default_servers)
    end

    context 'with no default_servers' do
      let(:args) { remove_arg 'default_servers' }
      it 'uses previous backends if no default_servers set' do
        expect(subject).to receive(:'reconfigure!').exactly(:once)
        backends = ['server1', 'server2']
        expect(subject.send(:set_backends, backends)).to equal(true)
        expect(subject.send(:set_backends, [])).to equal(false)
        expect(subject.backends).to eq(backends)
      end
    end

    context 'with no default_servers set and use_previous_backends disabled' do
      let(:args) {
        remove_arg 'default_servers'
        testargs.merge({'use_previous_backends' => false})
      }
      it 'removes all backends if no default_servers set and use_previous_backends disabled' do
        expect(subject).to receive(:'reconfigure!').exactly(:twice)
        backends = ['server1', 'server2']
        expect(subject.send(:set_backends, backends)).to equal(true)
        expect(subject.backends).to eq(backends)
        expect(subject.send(:set_backends, [])).to equal(true)
        expect(subject.backends).to eq([])
      end
    end

    it 'calls reconfigure only once for duplicate backends' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
      backends = ['server1', 'server2']
      expect(subject.send(:set_backends, backends)).to equal(true)
      expect(subject.backends).to eq(backends)
      expect(subject.send(:set_backends, backends)).to equal(false)
      expect(subject.backends).to eq(backends)
    end

    context 'with keep_default_servers set' do
      let(:args) {
        testargs.merge({'default_servers' => default_servers, 'keep_default_servers' => true})
      }
      it('keeps default_servers when setting backends') do
        backends = ['server1', 'server2']
        expect(subject).to receive(:'reconfigure!').exactly(:once)
        expect(subject.send(:set_backends, backends)).to equal(true)
        expect(subject.backends).to eq(backends + default_servers)
      end
    end
  end
end
