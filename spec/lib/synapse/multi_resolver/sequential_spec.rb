require 'spec_helper'
require 'synapse/service_watcher/multi/resolver/sequential'
require 'synapse/service_watcher/base/base'

describe Synapse::ServiceWatcher::Resolver::SequentialResolver do
  let(:watchers) { {'primary' => primary_watcher, 'secondary' => secondary_watcher} }

  let(:primary_watcher) {
    w = double(Synapse::ServiceWatcher::BaseWatcher)
    allow(w).to receive(:backends) { primary_healthy ? primary_backends: [] }
    allow(w).to receive(:ping?).and_return(primary_healthy)
    w
  }
  let(:primary_backends) { ["primary_1", "primary_2", "primary_3"] }
  let(:primary_healthy) { true }

  let(:secondary_watcher) {
    w = double(Synapse::ServiceWatcher::BaseWatcher)
    allow(w).to receive(:backends) { secondary_healthy ? secondary_backends: [] }
    allow(w).to receive(:ping?).and_return(secondary_healthy)
    w
  }
  let(:secondary_backends) { ["secondary_1", "secondary_2", "secondary_3"] }
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
    it 'returns primary backends' do
      expect(subject.merged_backends).to eq(primary_backends)
    end

    it 'calls backends only on first watcher' do
      expect(primary_watcher).to receive(:backends).exactly(:once).and_return(primary_backends)
      expect(secondary_watcher).not_to receive(:backends)
      subject.merged_backends
    end

    context 'when first watcher returns an empty list' do
      let(:primary_healthy) { false }

      it 'returns secondary backends' do
        expect(subject.merged_backends).to eq(secondary_backends)
      end

      it 'calls backends on secondary watcher' do
        expect(secondary_watcher).to receive(:backends).exactly(:once)
        subject.merged_backends
      end
    end

    context 'when both watchers return empty lists' do
      let(:primary_healthy) { false }
      let(:secondary_healthy) { false }

      it 'returns an empty list' do
        expect(subject.merged_backends).to eq([])
      end

      it 'calls backends on both watchers' do
        expect(primary_watcher).to receive(:backends).exactly(:once)
        expect(secondary_watcher).to receive(:backends).exactly(:once)
        subject.merged_backends
      end
    end

    context 'with secondary first in order' do
      let(:sequential_order) { ['secondary', 'primary'] }

      it 'returns secondary backends' do
        expect(subject.merged_backends).to eq(secondary_backends)
      end

      it 'calls backends only on second watcher' do
        expect(primary_watcher).not_to receive(:backends)
        expect(secondary_watcher).to receive(:backends).exactly(:once)
        subject.merged_backends
      end
    end
  end

  describe '#healthy?' do
    it 'calls ping? on the first watcher' do
      expect(primary_watcher).to receive(:ping?).exactly(:once).and_return(true)
      expect(primary_watcher).not_to receive(:ping?)
      subject.healthy?
    end

    context 'when only secondary is healthy' do
      let(:primary_healthy) { false }

      it 'returns true' do
        expect(subject.healthy?).to eq(true)
      end

      it 'calls ping on secondary' do
        expect(secondary_watcher).to receive(:ping?).exactly(:once).and_return(true)
        subject.healthy?
      end
    end

    context 'when only primary is healthy' do
      let(:secondary_healthy) { false }

      it 'returns true' do
        expect(subject.healthy?).to eq(true)
      end

      it 'calls ping on primary' do
        expect(primary_watcher).to receive(:ping?).exactly(:once).and_return(true)
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
        expect(secondary_watcher).to receive(:ping?).exactly(:once).and_return(true)
        expect(primary_watcher).not_to receive(:ping?)
        subject.healthy?
      end
    end
  end
end
