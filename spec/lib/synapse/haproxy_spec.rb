require 'spec_helper'

class MockWatcher; end;

describe Synapse::Haproxy do
  subject { Synapse::Haproxy.new(config['haproxy']) }

  it 'updating the config' do
    mockWatcher = double(Synapse::ServiceWatcher)
    subject.should_receive(:generate_config)
    subject.update_config([mockWatcher])
  end
end
