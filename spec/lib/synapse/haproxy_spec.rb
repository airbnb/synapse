require 'spec_helper'

class MockWatcher; end;

describe Synapse::Haproxy do
  subject { Synapse::Haproxy.new(config['haproxy']) }

  def createmockwatcher(backends)
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service')
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:haproxy).and_return({'server_options' => "check inter 2000 rise 3 fall 2"})
    mockWatcher
  end

  let(:mockwatcher) do
    createmockwatcher [{ 'host' => 'somehost', 'port' => '5555'}]
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

  it 'generates backend stanza with weight' do
    mockConfig = []
    expect(subject.generate_backend_stanza(createmockwatcher([{ 'weight' => 1, 'host' => 'somehost', 'port' => '5555'}]), mockConfig)).to eql(["\nbackend example_service", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 weight 1 check inter 2000 rise 3 fall 2"]])
  end

  it 'generates backend stanza with bad weight = 0' do
    mockConfig = []
    expect(subject.generate_backend_stanza(createmockwatcher([{ 'weight' => 'hi', 'host' => 'somehost', 'port' => '5555'}]), mockConfig)).to eql(["\nbackend example_service", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 weight 0 check inter 2000 rise 3 fall 2"]])
  end

  it 'generates backend stanza with nil weight = 0' do
    mockConfig = []
    expect(subject.generate_backend_stanza(createmockwatcher([{ 'weight' => nil, 'host' => 'somehost', 'port' => '5555'}]), mockConfig)).to eql(["\nbackend example_service", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 weight 0 check inter 2000 rise 3 fall 2"]])
  end

  it 'generates backend stanza without weight' do
    mockConfig = []
    expect(subject.generate_backend_stanza(createmockwatcher([{ 'host' => 'somehost', 'port' => '5555'}]), mockConfig)).to eql(["\nbackend example_service", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 check inter 2000 rise 3 fall 2"]])
  end



end
