require 'spec_helper'

require 'synapse/service_watcher/base/poll'
require 'concurrent'

describe Synapse::ServiceWatcher::PollWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end

  let(:mock_scheduler) do
    # Concurrent::TimerSet.new(:executor => :immediate)
    Concurrent::ImmediateExecutor.new
  end

  let(:config) do
    {
      'name' => 'test',
      'haproxy' => {},
      'discovery' => discovery,
    }
  end

  let(:discovery) { { 'method' => 'poll' } }

  subject { Synapse::ServiceWatcher::PollWatcher.new(config, mock_synapse, -> {}) }

  describe '#initialize' do
    it 'has a default check interval' do
      expect(subject.instance_variable_get(:@check_interval)).to eq(15)
    end
  end

  describe '#start' do
    it 'schedules a recurring task' do
      expect(mock_scheduler).to receive(:post).exactly(:once).with(0).and_call_original
      expect(mock_scheduler).to receive(:post).exactly(:once).with(15)
      expect(subject).to receive(:discover).exactly(:once)

      subject.start(mock_scheduler)
    end

    context 'when stopped' do
      before :each do
        subject.stop
      end

      it 'does not reschedule' do
        expect(mock_scheduler).to receive(:post).exactly(:once).with(0).and_call_original
        expect(mock_scheduler).not_to receive(:post).with(15)
        expect(subject).to receive(:discover).exactly(:once)

        subject.start(mock_scheduler)
      end
    end

    context 'with check_interval=0' do
      let(:discovery) { { 'method' => 'poll', 'check_interval' => 0 } }

      it 'keeps calling discover until stop is called' do
        count = 0
        expect(mock_scheduler).to receive(:post).with(0).exactly(15).times.and_wrap_original { |m, *args, &block|
          count += 1
          subject.stop if count >= 15

          m.call(*args) {
            block.call
          }
        }

        expect(subject).to receive(:discover).exactly(15).times

        subject.start(mock_scheduler)
      end
    end
  end
end
