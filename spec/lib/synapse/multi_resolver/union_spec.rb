require 'spec_helper'
require 'synapse/service_watcher/multi/resolver/union'
require 'synapse/service_watcher/base/base'

describe Synapse::ServiceWatcher::Resolver::UnionResolver do
  let(:watchers) { {'primary' => primary_watcher, 'secondary' => secondary_watcher} }

  let(:primary_watcher) {
    w = double(Synapse::ServiceWatcher::BaseWatcher)
    allow(w).to receive(:backends).and_return(primary_backends)
    allow(w).to receive(:ping?).and_return(primary_healthy)
    w
  }
  let(:primary_backends) { ["primary_1", "primary_2", "primary_3"] }
  let(:primary_healthy) { true }

  let(:secondary_watcher) {
    w = double(Synapse::ServiceWatcher::BaseWatcher)
    allow(w).to receive(:backends).and_return(secondary_backends)
    allow(w).to receive(:ping?).and_return(secondary_healthy)
    w
  }
  let(:secondary_backends) { ["secondary_1", "secondary_2", "secondary_3"] }
  let(:secondary_healthy) { true }

  let(:opts) { opts_valid }
  let(:opts_valid) { {'method' => 'union'} }

  subject { Synapse::ServiceWatcher::Resolver::UnionResolver.new(opts, watchers, -> {}) }

  describe '#initialize' do
    it 'constructs normally' do
      expect { subject }.not_to raise_error
    end

    context 'with invalid arguments' do
      let(:opts) { {'method' => 'bogus'} }

      it 'raises an error' do
        expect { subject }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#merged_backends' do
    it 'returns a combined unordered list of all backends' do
      subject.merged_backends.should =~ (primary_backends + secondary_backends)
    end

    it 'calls backends on all watchers' do
      expect(primary_watcher).to receive(:backends).exactly(:once)
      expect(secondary_watcher).to receive(:backends).exactly(:once)
      subject.merged_backends
    end

    context 'when one watcher returns an empty list' do
      let(:primary_backends) { [] }

      it 'returns only healthy watchers backends' do
        subject.merged_backends.should =~ secondary_backends
      end
    end

    context 'when duplicates exist' do
      # duplicates should be included because they are deduplicated in
      # set_backends.
      let(:primary_backends) { ["primary_1"] + secondary_backends }

      it 'includes duplicates' do
        subject.merged_backends.should =~ (primary_backends + secondary_backends)
      end
    end
  end

  describe '#healthy?' do
    it 'calls ping? on at least one watcher' do
      ping_count = 0
      allow(primary_watcher).to receive(:ping?) {
        ping_count += 1
        true
      }
      allow(secondary_watcher).to receive(:ping?) {
        ping_count += 1
        true
      }

      subject.healthy?
      expect(ping_count).to be >= 1
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
  end
end
