require 'spec_helper'

class Synapse::ServiceWatcher::BaseWatcher
  attr_reader :should_exit, :default_servers
end

describe Synapse::ServiceWatcher::BaseWatcher do
  let(:mocksynapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end
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

  ['name', 'discovery'].each do |to_remove|
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
      let(:matching_az) { 'us-east-1a' }
      let(:matching_labels) { [{'az' => matching_az}] * 2 }
      let(:non_matching_labels) { [{'az' => 'us-east-1b'}, {'az' => 'us-west-1a'}] }

      let(:matching_labeled_backends) do
        matching_labels.map{ |l| FactoryGirl.build(:backend, :labels => l) }
      end
      let(:non_matching_labeled_backends) do
        non_matching_labels.map{ |l| FactoryGirl.build(:backend, :labels => l) }
      end
      let(:non_labeled_backends) do
        [FactoryGirl.build(:backend, :labels => {})]
      end

      before do
        expect(subject).to receive(:'reconfigure!').exactly(:once)
        subject.send(:set_backends,
          matching_labeled_backends + non_matching_labeled_backends + non_labeled_backends)
      end

      let(:condition) { 'equals' }
      let(:label_filters) { [{ 'condition' => condition, 'label' => 'az', 'value' => 'us-east-1a' }] }
      let(:args) do
        testargs.merge({
          'discovery' => {
            'method' => 'base',
            'label_filters' => label_filters,
          }
        })
      end

      it 'removes all backends that do not match the label_filter' do
        expect(subject.backends).to contain_exactly(*matching_labeled_backends)
      end

      context 'when the condition is not-equals' do
        let(:condition) { 'not-equals' }

        it 'removes all backends that DO match the label_filter' do
          expect(subject.backends).to contain_exactly(*(non_labeled_backends + non_matching_labeled_backends))
        end
      end

      context 'with multiple labels and conditions conditions' do
        let(:matching_region) { 'region1' }
        let(:matching_labels) { [{'az' => matching_az, 'region' => matching_region}] * 2 }
        let(:non_matching_labels) do
          [
            {'az' => matching_az, 'region' => 'non-matching'},
            {'az' => 'non-matching', 'region' => matching_region},
            {'az' => 'non-matching', 'region' => 'non-matching'},
          ]
        end

        let(:label_filters) do
          [
            { 'condition' => 'equals', 'label' => 'az', 'value' => matching_az },
            { 'condition' => 'equals', 'label' => 'region', 'value' => matching_region },
          ]
        end

        it 'returns only backends that match all labels' do
          expect(subject.backends).to contain_exactly(*matching_labeled_backends)
        end
      end
    end
  end
end
