require 'spec_helper'

class Synapse::ServiceWatcher::BaseWatcher
  attr_reader :should_exit, :default_servers
end

describe Synapse::ServiceWatcher::BaseWatcher do
  let(:mocksynapse) { double() }
  subject { Synapse::ServiceWatcher::BaseWatcher.new(args, mocksynapse) }
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
    default_servers = [
      {'name' => 'default_server1', 'host' => 'default_server1', 'port' => 123},
      {'name' => 'default_server2', 'host' => 'default_server2', 'port' => 123}
    ]
    backends = [
      {'name' => 'server1', 'host' => 'server1', 'port' => 123},
      {'name' => 'server2', 'host' => 'server2', 'port' => 123}
    ]
    let(:args) { testargs.merge({'default_servers' => default_servers}) }

    it 'sets backends' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
      expect(subject.send(:set_backends, backends)).to equal(true)
      expect(subject.backends).to eq(backends)
    end

    it 'removes duplicate backends' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
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
        expect(subject.send(:set_backends, backends)).to equal(true)
        expect(subject.backends).to eq(backends)
        expect(subject.send(:set_backends, [])).to equal(true)
        expect(subject.backends).to eq([])
      end
    end

    it 'calls reconfigure only once for duplicate backends' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
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
        expect(subject).to receive(:'reconfigure!').exactly(:once)
        expect(subject.send(:set_backends, backends)).to equal(true)
        expect(subject.backends).to eq(backends + default_servers)
      end
    end

    context 'with label_filter set' do
      let(:matching_labeled_backends) { [
        { 'name' => 'server1', 'host' => 'server1', 'port' => 1111, 'labels' => { 'az' => 'us-east-1a' } },
        { 'name' => 'server2', 'host' => 'server2', 'port' => 2222, 'labels' => { 'az' => 'us-east-1a' } },
      ] }
      let(:non_matching_labeled_backends) { [
        { 'name' => 'server3', 'host' => 'server3', 'port' => 3333, 'labels' => { 'az' => 'us-west-1c' } },
        { 'name' => 'server4', 'host' => 'server4', 'port' => 4444, 'labels' => { 'az' => 'us-west-2a' } },
      ] }
      let(:non_labeled_backends) { [
        { 'name' => 'server5', 'host' => 'server5', 'port' => 5555 },
      ] }
      let(:args) {
        testargs.merge({ 'discovery' => {
          'method' => 'base',
          'label_filter' => { 'condition' => 'equals', 'label' => 'az', 'value' => 'us-east-1a' } }
        })
      }
      it 'removes all backends that do not match the label_filter' do
        expect(subject).to receive(:'reconfigure!').exactly(:once)
        subject.send(:set_backends, matching_labeled_backends + non_matching_labeled_backends +
                     non_labeled_backends)
        expect(subject.backends).to eq(matching_labeled_backends)
      end
    end

    context 'with weights defined' do
      let(:backends_with_weight)  { [
        { 'name' => 'server1', 'host' => 'server1', 'port' => 1111, 'weight' => 11 },
        { 'name' => 'server2', 'host' => 'server2', 'port' => 2222, 'weight' => 22 },
      ] }
      let(:non_matching_weight_backends) { [
        { 'name' => 'server1', 'host' => 'server1', 'port' => 1111, 'weight' => 33 },
        { 'name' => 'server2', 'host' => 'server2', 'port' => 2222, 'weight' => 22 },
      ] }
      let(:backends_with_non_matching_weight_duplicates) { [
        { 'name' => 'server1', 'host' => 'server1', 'port' => 1111, 'weight' => 11 },
        { 'name' => 'server1', 'host' => 'server1', 'port' => 1111, 'weight' => 33 },
        { 'name' => 'server2', 'host' => 'server2', 'port' => 2222, 'weight' => 22 },
      ] }
      it 'updates backends only when weights change' do
        expect(subject).to receive(:'reconfigure!').exactly(:twice)
        expect(subject.send(:set_backends, backends_with_weight)).to equal(true)
        expect(subject.backends).to eq(backends_with_weight)
        expect(subject.send(:set_backends, non_matching_weight_backends)).to equal(true)
        expect(subject.backends).to eq(non_matching_weight_backends)
        expect(subject.send(:set_backends, non_matching_weight_backends)).to equal(false)
        expect(subject.backends).to eq(non_matching_weight_backends)
      end
      it 'ignores duplicates even with non-matching weights' do
        expect(subject).to receive(:'reconfigure!').exactly(:once)
        expect(subject.send(:set_backends, backends_with_weight)).to equal(true)
        expect(subject.backends).to eq(backends_with_weight)
        expect(subject.send(:set_backends, backends_with_non_matching_weight_duplicates)).to equal(false)
        expect(subject.backends).to eq(backends_with_weight)
      end
    end
  end
end
