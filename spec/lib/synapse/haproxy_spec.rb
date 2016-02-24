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

  let(:mockwatcher_with_cookie_value_method_hash) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service')
    backends = [{ 'host' => 'somehost', 'port' => 5555}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:haproxy).and_return({'server_options' => "check inter 2000 rise 3 fall 2", 'cookie_value_method' => 'hash'})
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

  describe 'generate backend stanza in correct order' do
    let(:multiple_backends_stanza_map) do
      {
        'asc' => ["\nbackend example_service", [], ["\tserver somehost1:5555 somehost1:5555 cookie somehost1:5555 check inter 2000 rise 3 fall 2", "\tserver somehost2:5555 somehost2:5555 cookie somehost2:5555 check inter 2000 rise 3 fall 2", "\tserver somehost3:5555 somehost3:5555 cookie somehost3:5555 check inter 2000 rise 3 fall 2"]],
        'desc' => ["\nbackend example_service", [], ["\tserver somehost3:5555 somehost3:5555 cookie somehost3:5555 check inter 2000 rise 3 fall 2", "\tserver somehost2:5555 somehost2:5555 cookie somehost2:5555 check inter 2000 rise 3 fall 2", "\tserver somehost1:5555 somehost1:5555 cookie somehost1:5555 check inter 2000 rise 3 fall 2"]],
        'no_shuffle' => ["\nbackend example_service", [], ["\tserver somehost1:5555 somehost1:5555 cookie somehost1:5555 check inter 2000 rise 3 fall 2", "\tserver somehost3:5555 somehost3:5555 cookie somehost3:5555 check inter 2000 rise 3 fall 2", "\tserver somehost2:5555 somehost2:5555 cookie somehost2:5555 check inter 2000 rise 3 fall 2"]]
      }
    end

    let(:mockwatcher_with_multiple_backends) do
      mockWatcher = double(Synapse::ServiceWatcher)
      allow(mockWatcher).to receive(:name).and_return('example_service')
      backends = [{ 'host' => 'somehost1', 'port' => 5555}, {'host' => 'somehost3', 'port' => 5555}, { 'host' => 'somehost2', 'port' => 5555}]
      allow(mockWatcher).to receive(:backends).and_return(backends)
      mockWatcher
    end

    ['asc', 'desc', 'no_shuffle'].each do |order_option|
      context "when #{order_option} is specified for backend_order" do
        it 'generates backend stanza in correct order' do
          mockConfig = []
          allow(mockwatcher_with_multiple_backends).to receive(:haproxy).and_return({'server_options' => "check inter 2000 rise 3 fall 2", 'backend_order' => order_option})
          expect(subject.generate_backend_stanza(mockwatcher_with_multiple_backends, mockConfig)).to eql(multiple_backends_stanza_map[order_option])
        end
      end
    end
  end

  it 'hashes backend name as cookie value' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher_with_cookie_value_method_hash, mockConfig)).to eql(["\nbackend example_service", [], ["\tserver somehost:5555 somehost:5555 cookie 9e736eef2f5a1d441e34ade3d2a8eb1e3abb1c92 check inter 2000 rise 3 fall 2"]])
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
