require 'spec_helper'

class MockWatcher; end;

describe Synapse::Haproxy do
  subject { Synapse::Haproxy.new(config['haproxy']) }

  let(:mockwatcher) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service')
    backends = [{ 'host' => 'somehost', 'port' => 5555}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:haproxy).and_return({'server_options' => "check inter 2000 rise 3 fall 2"})
    mockWatcher
  end

  let(:mockwatcher_with_server_options) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'haproxy_server_options' => 'backup'}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:haproxy).and_return({'server_options' => "check inter 2000 rise 3 fall 2"})
    mockWatcher
  end

  let(:mockwatcher_frontend) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service')
    allow(mockWatcher).to receive(:haproxy).and_return('port' => 2200)
    mockWatcher
  end

  let(:mockwatcher_frontend_with_bind_address) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service')
    allow(mockWatcher).to receive(:haproxy).and_return('port' => 2200, 'bind_address' => "127.0.0.3")
    mockWatcher
  end


  it 'updating the config' do
    expect(subject).to receive(:generate_config)
    subject.update_config([mockwatcher])
  end

  it 'generates backend stanza' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher, mockConfig)).to eql(["\nbackend example_service", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 check inter 2000 rise 3 fall 2"]])
  end

  it 'generates backend stanza without cookies for tcp mode' do
    mockConfig = ['mode tcp']
    expect(subject.generate_backend_stanza(mockwatcher, mockConfig)).to eql(["\nbackend example_service", ["\tmode tcp"], ["\tserver somehost:5555 somehost:5555 check inter 2000 rise 3 fall 2"]])
  end

  it 'respects haproxy_server_options' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher_with_server_options, mockConfig)).to eql(["\nbackend example_service", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 check inter 2000 rise 3 fall 2 backup"]])
  end

  it 'generates frontend stanza ' do
    mockConfig = []
    expect(subject.generate_frontend_stanza(mockwatcher_frontend, mockConfig)).to eql(["\nfrontend example_service", [], "\tbind localhost:2200", "\tdefault_backend example_service"])
  end

  it 'respects frontend bind_address ' do
    mockConfig = []
    expect(subject.generate_frontend_stanza(mockwatcher_frontend_with_bind_address, mockConfig)).to eql(["\nfrontend example_service", [], "\tbind 127.0.0.3:2200", "\tdefault_backend example_service"])
  end

end
