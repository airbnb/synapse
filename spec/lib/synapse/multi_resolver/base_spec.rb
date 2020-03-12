require 'spec_helper'
require 'synapse/service_watcher/multi/resolver/base'
require 'synapse/service_watcher/base/base'

describe Synapse::ServiceWatcher::Resolver::BaseResolver do
  let(:opts) {
    {'method' => 'base'}
  }

  let(:watchers) {
    [
      instance_double(Synapse::ServiceWatcher::BaseWatcher)
    ]
  }

  let(:notification_callback) { -> {} }

  subject {
    Synapse::ServiceWatcher::Resolver::BaseResolver.new(opts, watchers, notification_callback)
  }

  describe "#initialize" do
    context 'with valid options' do
      it 'constructs properly' do
        expect { subject }.not_to raise_error
      end
    end

    context 'with invalid method' do
      let(:opts) {
        {'method' => 'bogus'}
      }

      it 'raises an error' do
        expect { subject }.to raise_error(ArgumentError)
      end
    end

    context 'without watchers' do
      let(:watchers) {[]}

      it 'raises an error' do
        expect { subject }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#start" do
    it 'does not raise an error' do
      expect { subject.start }.not_to raise_error
    end
  end

  describe "#stop" do
    it 'does not raise an error' do
      expect { subject.stop }.not_to raise_error
    end
  end

  describe "#merged_backends" do
    it 'returns an empty list by default' do
      expect(subject.merged_backends).to eq([])
    end
  end

  describe "#healthy?" do
    it 'returns true by default' do
      expect(subject.healthy?).to eq(true)
    end
  end

  describe 'send_notification' do
    it 'calls the provided callback' do
      expect(notification_callback).to receive(:call).exactly(:once)
      subject.send(:send_notification)
    end
  end
end
