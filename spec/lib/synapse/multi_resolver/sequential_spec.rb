require 'spec_helper'
require 'synapse/service_watcher/multi/resolver/sequential'
require 'synapse/service_watcher/base/base'

describe Synapse::ServiceWatcher::Resolver::SequentialResolver do
  let(:watchers) { {'primary' => primary_watcher, 'secondary' => secondary_watcher} }

  let(:primary_watcher) {
    w = double(Synapse::ServiceWatcher::BaseWatcher)
    allow(w).to receive(:backends) { primary_healthy ? primary_backends: [] }
    allow(w).to receive(:config_for_generator) { primary_healthy ? primary_config_for_generator: {} }
    allow(w).to receive(:ping?).and_return(primary_healthy)
    allow(w).to receive(:watching?).and_return(primary_healthy)
    w
  }
  let(:primary_backends) { ["primary_1", "primary_2", "primary_3"] }
  let(:primary_config_for_generator) { {'haproxy' => 'primary config'} }
  let(:primary_healthy) { true }

  let(:secondary_watcher) {
    w = double(Synapse::ServiceWatcher::BaseWatcher)
    allow(w).to receive(:backends) { secondary_healthy ? secondary_backends: [] }
    allow(w).to receive(:config_for_generator) { secondary_healthy ? secondary_config_for_generator: {} }
    allow(w).to receive(:ping?).and_return(secondary_healthy)
    allow(w).to receive(:watching?).and_return(secondary_healthy)
    w
  }
  let(:secondary_backends) { ["secondary_1", "secondary_2", "secondary_3"] }
  let(:secondary_config_for_generator) { {'haproxy' => 'secondary config'} }
  let(:secondary_healthy) { true }

  let(:opts) { opts_valid }
  let(:opts_valid) { {'method' => 'sequential', 'sequential_order' => sequential_order} }
  let(:sequential_order) { ['primary', 'secondary'] }

  subject { Synapse::ServiceWatcher::Resolver::SequentialResolver.new(opts, watchers, -> {}) }

  describe '#initialize' do
    it 'constructs normally' do
      expect { subject }.not_to raise_error
    end

    context 'without defined sequential_order' do
      let(:opts) { {'method' => 'sequential'} }

      it 'raises an error' do
        expect { subject }.to raise_error(ArgumentError)
      end
    end

    context 'with unknown watchers' do
      let(:sequential_order) { ['primary', 'bogus', 'secondary'] }

      it 'raises an error' do
        expect { subject }.to raise_error(ArgumentError)
      end
    end

    context 'with missing watchers' do
      let(:sequential_order) { [] }

      it 'raises an error' do
        expect { subject }.to raise_error(ArgumentError)
      end
    end

    context 'with invalid method' do
      let(:opts) { {'method' => 'bogus'} }

      it 'raises an error' do
        expect { subject }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#merged_backends' do
    before :each do
      subject.start
    end

    it 'returns primary backends' do
      expect(subject.merged_backends).to eq(primary_backends)
    end

    it 'calls backends only on first watcher' do
      expect(primary_watcher).to receive(:backends).at_least(:once).and_return(primary_backends)
      expect(secondary_watcher).not_to receive(:backends)
      subject.merged_backends
    end

    context 'when first watcher returns an empty list' do
      let(:primary_healthy) { false }

      it 'returns secondary backends' do
        expect(subject.merged_backends).to eq(secondary_backends)
      end

      it 'calls backends on secondary watcher' do
        expect(secondary_watcher).to receive(:backends).at_least(:once)
        subject.merged_backends
      end
    end

    context 'when both watchers are unhealthy' do
      let(:primary_healthy) { false }
      let(:secondary_healthy) { false }

      it 'returns an empty list' do
        expect(subject.merged_backends).to eq([])
      end
    end

    context 'with secondary first in order' do
      let(:sequential_order) { ['secondary', 'primary'] }

      it 'returns secondary backends' do
        expect(subject.merged_backends).to eq(secondary_backends)
      end

      it 'calls backends only on second watcher' do
        expect(primary_watcher).not_to receive(:backends)
        expect(secondary_watcher).to receive(:backends).at_least(:once)
        subject.merged_backends
      end
    end
  end

  describe '#merged_config_for_generator' do
    before :each do
      subject.start
    end

    it 'returns primary config_for_generator' do
      expect(subject.merged_config_for_generator).to eq(primary_config_for_generator)
    end

    it 'calls config_for_generator only on first watcher' do
      expect(primary_watcher).to receive(:config_for_generator).at_least(:once).and_return(primary_config_for_generator)
      expect(secondary_watcher).not_to receive(:config_for_generator)
      subject.merged_config_for_generator
    end

    context 'when first watcher returns an empty list' do
      let(:primary_healthy) { false }

      it 'returns secondary config_for_generator' do
        expect(subject.merged_config_for_generator).to eq(secondary_config_for_generator)
      end

      it 'calls config_for_generator on secondary watcher' do
        expect(secondary_watcher).to receive(:config_for_generator).at_least(:once)
        subject.merged_config_for_generator
      end
    end

    context 'when both watchers are unhealthy' do
      let(:primary_healthy) { false }
      let(:secondary_healthy) { false }

      it 'returns an empty config' do
        expect(subject.merged_config_for_generator).to eq({})
      end
    end

    context 'with secondary first in order' do
      let(:sequential_order) { ['secondary', 'primary'] }

      it 'returns secondary config_for_generator' do
        expect(subject.merged_config_for_generator).to eq(secondary_config_for_generator)
      end

      it 'calls config_for_generator only on second watcher' do
        expect(primary_watcher).not_to receive(:config_for_generator)
        expect(secondary_watcher).to receive(:config_for_generator).at_least(:once)
        subject.merged_config_for_generator
      end
    end
  end

  describe '#healthy?' do
    before :each do
      subject.start
    end

    it 'calls ping? on the first watcher' do
      expect(primary_watcher).to receive(:ping?).at_least(:once).and_return(true)
      expect(secondary_watcher).not_to receive(:ping?)
      subject.healthy?
    end

    context 'when only secondary is healthy' do
      let(:primary_healthy) { false }

      it 'returns true' do
        expect(subject.healthy?).to eq(true)
      end

      it 'calls ping on secondary' do
        expect(secondary_watcher).to receive(:ping?).at_least(:once).and_return(true)
        subject.healthy?
      end
    end

    context 'when only primary is healthy' do
      let(:secondary_healthy) { false }

      it 'returns true' do
        expect(subject.healthy?).to eq(true)
      end

      it 'calls ping on primary' do
        expect(primary_watcher).to receive(:ping?).at_least(:once).and_return(true)
        subject.healthy?
      end
    end

    context 'when both watchers are healthy' do
      it 'returns true' do
        expect(subject.healthy?).to eq(true)
      end
    end

    context 'when both watchers are unhealthy' do
      let(:primary_healthy) { false }
      let(:secondary_healthy) { false }

      it 'returns false' do
        expect(subject.healthy?).to eq(false)
      end
    end

    context 'with reversed order' do
      let(:sequential_order) { ['secondary', 'primary'] }

      it 'calls ping? on secondary' do
        expect(secondary_watcher).to receive(:ping?).at_least(:once).and_return(true)
        expect(primary_watcher).not_to receive(:ping?)
        subject.healthy?
      end
    end
  end

  describe 'pick_watcher' do
    context 'when all watchers are healthy' do
      before :each do
        subject.instance_variable_get(:@watcher_setting).set('secondary')
      end

      it 'picks first' do
        expect(primary_watcher).to receive(:ping?).at_least(:once)
        expect(primary_watcher).to receive(:backends).exactly(:once)
        expect(primary_watcher).to receive(:config_for_generator).exactly(:once)

        expect(secondary_watcher).not_to receive(:ping?)
        expect(secondary_watcher).not_to receive(:backends)
        expect(secondary_watcher).not_to receive(:config_for_generator)

        expect { subject.send(:pick_watcher) }.to change { subject.instance_variable_get(:@watcher_setting).get }.to ('primary')
      end

      it 'sends a notification' do
        expect(subject).to receive(:send_notification).exactly(:once)
        subject.send(:pick_watcher)
      end
    end

    context 'when first watcher is unhealthy' do
      let(:primary_healthy) { false }

      it 'picks second' do
        expect(secondary_watcher).to receive(:ping?).at_least(:once)
        expect(secondary_watcher).to receive(:backends).exactly(:once)
        expect(secondary_watcher).to receive(:config_for_generator).exactly(:once)

        expect { subject.send(:pick_watcher) }.to change { subject.instance_variable_get(:@watcher_setting).get }.to ('secondary')
      end

      it 'sends a notification' do
        expect(subject).to receive(:send_notification).exactly(:once)
        subject.send(:pick_watcher)
      end
    end

    context 'in reversed order' do
      let(:sequential_order) { ['secondary', 'primary'] }
      before :each do
        subject.instance_variable_get(:@watcher_setting).set('primary')
      end

      it 'picks secondary first' do
        expect { subject.send(:pick_watcher) }.to change { subject.instance_variable_get(:@watcher_setting).get }.to ('secondary')
      end
    end

    context 'when watcher does not change' do
      before :each do
        subject.instance_variable_get(:@watcher_setting).set('primary')
      end

      it 'does not send a notification' do
        expect(subject).not_to receive(:send_notification)
        subject.send(:pick_watcher)
      end
    end
  end
end
