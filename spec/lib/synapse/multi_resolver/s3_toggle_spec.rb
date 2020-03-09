require 'spec_helper'
require 'synapse/service_watcher/multi/resolver/s3_toggle'
require 'synapse/service_watcher/base/base'

describe Synapse::ServiceWatcher::Resolver::S3ToggleResolver do
  let(:watchers) { {'primary' => primary_watcher, 'secondary' => secondary_watcher} }

  let(:primary_watcher) {
    w = double(Synapse::ServiceWatcher::BaseWatcher)
    allow(w).to receive(:backends).and_return(primary_backends)
    allow(w).to receive(:ping?).and_return(true)
    w
  }
  let(:primary_backends) { ["primary_1", "primary_2", "primary_3"] }

  let(:secondary_watcher) {
    w = double(Synapse::ServiceWatcher::BaseWatcher)
    allow(w).to receive(:backends).and_return(secondary_backends)
    allow(w).to receive(:ping?).and_return(true)
    w
  }
  let(:secondary_backends) { ["secondary_1", "secondary_2", "secondary_3"] }

  let(:opts) { opts_valid }
  let(:opts_valid) {
    {'method' => 's3_toggle',
       's3_url' => 's3://bucket/path1/path2',
       's3_polling_interval_seconds' => 60}
  }

  subject { Synapse::ServiceWatcher::Resolver::S3ToggleResolver.new(opts, watchers) }

  describe '#initialize' do
    context 'with valid arguments' do
      it 'constructs normally' do
        expect { subject }.not_to raise_error
      end
    end

    context 'with invalid arguments' do
      context 'with invalid method' do
        let(:opts) { opts_valid.merge({'method' => 'bogus'}) }

        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end

      context 'with invalid s3_url' do
        let(:opts) { opts_valid.merge({'s3_url' => 'bogus'}) }

        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end

      context 'with invalid s3_polling_interval_seconds' do
        let(:opts) { opts_valid.merge({'s3_polling_interval_seconds' => 'bogus'}) }

        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end

      %w(method s3_url s3_polling_interval_seconds).each do |opt|
        context "missing #{opt}" do
          let(:opts) {
            opts_valid.delete(opt)
            opts_valid
          }

          it 'raises an error' do
            expect { subject }.to raise_error(ArgumentError)
          end
        end
      end

      context 'without watchers' do
        let(:watchers) { [] }
        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe '#start' do
    it 'starts a thread' do
      expect(Thread).to receive(:new)
    end

    it 'calls #set_watcher' do
      allow(Thread).to receive(:new) do |&block|
        block.call
      end

      expect(subject).to receive(:read_s3_file)
      expect(subject).to receive(:set_watcher)
      subject.start
    end
  end

  describe '#stop' do
    context 'with a thread running' do
      let(:mock_thread) {
        thr = double(Thread)
        allow(Thread).to receive(:new).and_return(thr)
        thr
      }

      it 'waits to exit' do
        expect(mock_thread).to receive(:join)
        subject.stop
      end
    end

    context 'without a thread running' do
      it 'continues silently' do
        subject.stop
      end
    end
  end

  describe '#merged_backends' do
    before :each do
      subject.instance_variable_set(:@watcher_setting, 'secondary')
    end

    it 'calls #backends on current watcher' do
      expect(secondary_watcher).to receive(:backends)
      subject.merged_backends
    end

    it 'does not call #backends on other watchers' do
      expect(primary_watcher).not_to receive(:backends)
      subject.merged_backends
    end

    it 'returns backends from current watcher' do
      expect(subject.merged_backends).to eq(secondary_backends)
    end
  end

  describe '#healthy?' do
    before :each do
      subject.instance_variable_set(:@watcher_setting, 'secondary')
    end

    it 'calls #ping? on current watcher' do
      expect(secondary_watcher).to receive(:ping?)
      subject.healthy?
    end

    it 'does not call #ping? on other watchers' do
      expect(primary_watcher).not_to receive(:ping?)
      subject.healthy?
    end

    context 'when current watcher returns true' do
      before :each do
        allow(secondary_watcher).to receive(:ping?).and_return(true)
      end

      it 'returns true' do
        expect(subject.healthy?).to eq(true)
      end
    end

    context 'when current watcher returns false' do
      before :each do
        allow(secondary_watcher).to receive(:ping?).and_return(true)
      end

      it 'returns false' do
        expect(subject.healthy?).to eq(false)
      end
    end

    context 'when other watchers return unhealthy' do
      before :each do
        allow(secondary_watcher).to receive(:ping?).and_return(true)
        allow(primary_watcher).to receive(:ping?).and_return(false)
      end

      it 'still returns true' do
        expect(subject.healthy?).to eq(true)
      end
    end
  end

  describe 'set_watcher' do
    let(:watcher_weights) { {'primary' => 0, 'secondary' => 100} }

    it 'sets @watcher_setting' do
      expect(subject).instance_variable_get(:@watcher_setting, 'secondary')
      subject.set_watcher(watcher_weights)
    end

    it 'picks between the watchers by weight'

    context 'when primary has all weight' do
      let(:watcher_weights) { {'primary' => 100, 'secondary' => 0} }

      it 'returns primary' do
        expect(subject).instance_variable_get(:@watcher_setting, 'primary')
        subject.set_watcher(watcher_weights)
      end
    end

    context 'when called multiple times' do
      let(:watcher_weights) { {'primary' => 50, 'secondary' => 50} }

      it 'deterministically returns the same result' do
        expect(subject).instance_variable_get(:@watcher_setting, 'primary')
        subject.set_watcher(watcher_weights)
      end
    end

    context 'when weights are empty' do
      let(:watcher_weights) {}

      it 'returns primary' do
        expect(subject).instance_variable_get(:@watcher_setting, 'primary')
        subject.set_watcher(watcher_weights)
      end
    end

    context 'when weights add up to more than 100' do
      let(:watcher_weights) { {'primary' => 50, 'secondary' => 100} }

      it 'still sets watcher properly'
    end
  end

  describe 'read_s3_file' do
    let(:s3_data) { {'primary' => 50, 'secondary' => 50} }

    it 'properly parses response'
    it 'calls S3 API with proper bucket and key'

    context 'with s3 errors' do
      it 'retries'
      it 'exponentially backs off'
    end
  end

  describe 'parse_s3_url' do
    it 'returns components'

    context 'with invalid format' do
      it 'raises an error'
    end
  end
end
