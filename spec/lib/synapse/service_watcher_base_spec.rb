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

  context "with normal arguments" do
    let(:args) { testargs }

    it 'can construct properly' do
      expect { subject }.not_to raise_error
    end

    it 'properly sets instance variables' do
      # ensure that synapse is not mistaken for reconfigure_callback
      expect(subject.instance_variable_get(:@synapse)).to eq(mocksynapse)
      expect(subject.instance_variable_get(:@reconfigure_callback).nil?).to eq(false)
      expect(subject.instance_variable_get(:@reconfigure_callback)).not_to eq(mocksynapse)
    end
  end

  ['name', 'discovery'].each do |to_remove|
    context "without #{to_remove} argument" do
      let(:args) { remove_arg to_remove }

      it 'raises error' do
        expect { subject }.to raise_error(ArgumentError, "missing required option #{to_remove}")
      end
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

  describe "set_backends" do
    default_servers = [
      {'name' => 'default_server1', 'host' => 'default_server1', 'port' => 123},
      {'name' => 'default_server2', 'host' => 'default_server2', 'port' => 123}
    ]
    backends = [
      {'name' => 'server1', 'host' => 'server1', 'port' => 123},
      {'name' => 'server2', 'host' => 'server2', 'port' => 123}
    ]
    config_for_generator = {
      "haproxy" => {
        "frontend" => [
          "binding ::1:1111"
        ],
        "listen" => [
          "mode http",
          "option httpchk GET /health",
          "timeout  client  300s",
          "timeout  server  300s",
          "option httplog"
        ],
        "port" => 1111,
        "server_options" => "check inter 60s fastinter 2s downinter 5s rise 3 fall 2",
      }
    }
    let(:args) { testargs.merge({'default_servers' => default_servers}) }

    it 'sets backends' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
      expect(subject.send(:set_backends, backends)).to equal(true)
      expect(subject.backends).to eq(backends)
    end

    it 'sets backends with config for generator' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
      expect(subject.send(:set_backends, backends, config_for_generator)).to equal(true)
      expect(subject.backends).to eq(backends)
      expect(subject.config_for_generator).to  eq(config_for_generator)
    end

    it 'calls reconfigure for duplicate backends but different config_for_generator' do
      allow(subject).to receive(:backends).and_return(backends)
      expect(subject).to receive(:'reconfigure!').exactly(:once)
      expect(subject.send(:set_backends, backends, config_for_generator)).to equal(true)
      expect(subject.config_for_generator).to eq(config_for_generator)
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

    it 'keeps the current config_for_generator if no config discovered from ZK' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
      # set config_for_generator to some valid config
      expect(subject.send(:set_backends, backends, config_for_generator)).to equal(true)
      expect(subject.backends).to eq(backends)
      expect(subject.config_for_generator).to eq(config_for_generator)

      # re-set config_for_generator to empty
      expect(subject.send(:set_backends, backends, {})).to equal(false)
      expect(subject.backends).to eq(backends)
      expect(subject.config_for_generator).to eq(config_for_generator)
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

    it 'calls reconfigure only once for duplicate backends and config_for_generator' do
      expect(subject).to receive(:'reconfigure!').exactly(:once)
      expect(subject.send(:set_backends, backends, config_for_generator)).to equal(true)
      expect(subject.backends).to eq(backends)
      expect(subject.config_for_generator).to eq(config_for_generator)
      expect(subject.send(:set_backends, backends, config_for_generator)).to equal(false)
      expect(subject.backends).to eq(backends)
      expect(subject.config_for_generator).to eq(config_for_generator)
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

  describe "reconfigure!" do
    let(:args) { testargs }

    context "without custom callback" do
      subject { Synapse::ServiceWatcher::BaseWatcher.new(args, mocksynapse) }

      it "calls synapse reconfigure" do
        expect(mocksynapse).to receive(:reconfigure!).exactly(:once)
        subject.send(:reconfigure!)
      end

      it "increments revision" do
        allow(mocksynapse).to receive(:reconfigure!)
        expect{subject.send(:reconfigure!)}.to change{subject.revision}.by 1
      end
    end

    context "with explicit nil custom callback" do
      subject { Synapse::ServiceWatcher::BaseWatcher.new(args, nil, mocksynapse) }

      it "calls synapse reconfigure" do
        expect(mocksynapse).to receive(:reconfigure!).exactly(:once)
        subject.send(:reconfigure!)
      end

      it "increments revision" do
        allow(mocksynapse).to receive(:reconfigure!).exactly(:once)
        expect{subject.send(:reconfigure!)}.to change{subject.revision}.by 1
      end
    end

    context "with custom callback" do
      let(:cb) { lambda {} }
      subject { Synapse::ServiceWatcher::BaseWatcher.new(args, cb, mocksynapse) }

      it "calls custom callback" do
        expect(mocksynapse).not_to receive(:reconfigure!)
        expect(cb).to receive(:call).exactly(:once)

        subject.send(:reconfigure!)
      end

      it "increments revision" do
        allow(cb).to receive(:call).exactly(:once)
        expect{subject.send(:reconfigure!)}.to change{subject.revision}.by 1
      end
    end
  end
end
