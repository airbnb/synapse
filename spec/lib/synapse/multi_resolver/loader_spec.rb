require 'spec_helper'
require 'synapse/service_watcher/base/base'
require 'synapse/service_watcher/multi/resolver'
require 'synapse/service_watcher/multi/resolver/base'

describe Synapse::ServiceWatcher::Resolver do
  subject { Synapse::ServiceWatcher::Resolver }

  let(:watchers) {
    [
      instance_double(Synapse::ServiceWatcher::BaseWatcher)
    ]
  }

  describe ".load_resolver" do
    let(:config) { {'method' => 'base'} }
    subject {
      Synapse::ServiceWatcher::Resolver
    }

    context 'with method => base' do
      it 'creates the base resolver' do
        expect(subject::BaseResolver).to receive(:new).exactly(:once).with(config, watchers)
        expect { subject.load_resolver(config, watchers) }.not_to raise_error
      end
    end

    context 'with bogus method' do
      let(:config) { {'method' => 'bogus'} }

      it 'raises an error' do
        expect(subject::BaseResolver).not_to receive(:new)
        expect { subject.load_resolver(config, watchers) }.to raise_error(ArgumentError)
      end
    end
  end
end
