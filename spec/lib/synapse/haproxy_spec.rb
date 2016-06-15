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
    allow(mockWatcher).to receive(:name).and_return('example_service2')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'haproxy_server_options' => 'backup'}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:haproxy).and_return({'server_options' => "check inter 2000 rise 3 fall 2"})
    mockWatcher
  end

  let(:mockwatcher_with_cookie_value_method_hash) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service3')
    backends = [{ 'host' => 'somehost', 'port' => 5555}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:haproxy).and_return({'server_options' => "check inter 2000 rise 3 fall 2", 'cookie_value_method' => 'hash'})
    mockWatcher
  end

  let(:mockwatcher_frontend) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service4')
    allow(mockWatcher).to receive(:haproxy).and_return('port' => 2200)
    mockWatcher
  end

  let(:mockwatcher_frontend_with_bind_address) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service5')
    allow(mockWatcher).to receive(:haproxy).and_return('port' => 2200, 'bind_address' => "127.0.0.3")
    mockWatcher
  end

  describe '#name' do
    it 'returns haproxy' do
      expect(subject.name).to eq('haproxy')
    end
  end

  describe '#update_config' do
    let(:watchers) { [mockwatcher_frontend, mockwatcher_frontend_with_bind_address] }

    shared_context 'generate_config is stubbed out' do
      let(:new_config) { 'this is a new config!' }
      before { expect(subject).to receive(:generate_config).and_return(new_config) }
    end

    it 'always updates the config' do
      expect(subject).to receive(:generate_config).with(watchers)
      subject.update_config(watchers)
    end

    context 'when we support socket updates' do
      let(:socket_file_path) { 'socket_file_path' }
      before do
        config['haproxy']['do_socket'] = true
        config['haproxy']['socket_file_path'] = socket_file_path
      end

      include_context 'generate_config is stubbed out'

      it 'updates backends via the socket' do
        expect(subject).to receive(:update_backends_at).with(socket_file_path, watchers)
        subject.update_config(watchers)
      end

      context 'when we specify multiple stats sockets' do
        let(:socket_file_path) { ['socket_file_path1', 'socket_file_path2'] }

        it 'updates all of them' do
          expect(subject).to receive(:update_backends_at).exactly(socket_file_path.count).times
          subject.update_config(watchers)
        end
      end
    end

    context 'when we do not support socket updates' do
      include_context 'generate_config is stubbed out'
      before { config['haproxy']['do_socket'] = false }

      it 'does not update the backends' do
        expect(subject).to_not receive(:update_backends_at)
        subject.update_config(watchers)
      end
    end

    context 'if we support config writes' do
      include_context 'generate_config is stubbed out'
      before { config['haproxy']['do_writes'] = true }

      it 'writes the new config' do
        expect(subject).to receive(:write_config).with(new_config)
        subject.update_config(watchers)
      end
    end

    context 'if we do not support config writes' do
      include_context 'generate_config is stubbed out'
      before { config['haproxy']['do_writes'] = false }

      it 'does not write the config' do
        expect(subject).to_not receive(:write_config)
        subject.update_config(watchers)
      end
    end

    context 'when we support config writes and reloads but not socket updates' do
      include_context 'generate_config is stubbed out'

      before do
        config['haproxy']['do_writes'] = true
        config['haproxy']['do_reloads'] = true
        config['haproxy']['do_socket'] = false
      end

      it 'always does a reload' do
        expect(subject).to receive(:write_config).with(new_config)
        expect(subject).to receive(:restart)
        subject.update_config(watchers)
      end
    end
  end

  describe '#tick' do
    it 'updates the state file at regular intervals' do
      expect(subject).to receive(:update_state_file).twice
      (described_class::STATE_FILE_UPDATE_INTERVAL + 1).times do
        subject.tick({})
      end
    end
  end

  describe '#update_state_file' do
    let(:watchers) { [mockwatcher, mockwatcher_with_server_options] }
    let(:state_file_ttl) { 60 } # seconds

    before do
      config['haproxy']['state_file_path'] = '/statefile'
      config['haproxy']['state_file_ttl'] = state_file_ttl
      allow(subject).to receive(:write_data_to_state_file)
    end

    it 'adds backends along with timestamps' do
      subject.update_state_file(watchers)
      data = subject.send(:seen)

      watcher_names = watchers.map{ |w| w.name }
      expect(data.keys).to contain_exactly(*watcher_names)

      watchers.each do |watcher|
        backend_names = watcher.backends.map{ |b| subject.construct_name(b) }
        expect(data[watcher.name].keys).to contain_exactly(*backend_names)

        backend_names.each do |backend_name|
          expect(data[watcher.name][backend_name]).to include('timestamp')
        end
      end
    end

    context 'when the state file contains backends not in the watcher' do
      it 'keeps them in the config' do
        subject.update_state_file(watchers)

        expect do
          watchers.each do |watcher|
            allow(watcher).to receive(:backends).and_return([])
          end
          subject.update_state_file(watchers)
        end.to_not change { subject.send(:seen) }
      end

      context 'if those backends are stale' do
        it 'removes those backends' do
          subject.update_state_file(watchers)

          watchers.each do |watcher|
            allow(watcher).to receive(:backends).and_return([])
          end

          # the final +1 puts us over the expiry limit
          Timecop.travel(Time.now + state_file_ttl + 1) do
            subject.update_state_file(watchers)
            data = subject.send(:seen)
            watchers.each do |watcher|
              expect(data[watcher.name]).to be_empty
            end
          end
        end
      end
    end
  end

  it 'generates backend stanza' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher, mockConfig)).to eql(["\nbackend example_service", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 check inter 2000 rise 3 fall 2"]])
  end

  describe 'generate backend stanza in correct order' do
    let(:multiple_backends_stanza_map) do
      {
        'asc' => [
          "\nbackend example_service",
          [],
          ["\tserver somehost1_10.11.11.11:5555 10.11.11.11:5555 cookie somehost1_10.11.11.11:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost2_10.10.10.10:5555 10.10.10.10:5555 cookie somehost2_10.10.10.10:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost3_10.22.22.22:5555 10.22.22.22:5555 cookie somehost3_10.22.22.22:5555 check inter 2000 rise 3 fall 2"
          ]
        ],
        'desc' => [
          "\nbackend example_service",
          [],
          ["\tserver somehost3_10.22.22.22:5555 10.22.22.22:5555 cookie somehost3_10.22.22.22:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost2_10.10.10.10:5555 10.10.10.10:5555 cookie somehost2_10.10.10.10:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost1_10.11.11.11:5555 10.11.11.11:5555 cookie somehost1_10.11.11.11:5555 check inter 2000 rise 3 fall 2"
          ]
        ],
        'no_shuffle' => [
          "\nbackend example_service",
          [],
          ["\tserver somehost1_10.11.11.11:5555 10.11.11.11:5555 cookie somehost1_10.11.11.11:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost3_10.22.22.22:5555 10.22.22.22:5555 cookie somehost3_10.22.22.22:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost2_10.10.10.10:5555 10.10.10.10:5555 cookie somehost2_10.10.10.10:5555 check inter 2000 rise 3 fall 2"
          ]
        ]
      }
    end

    let(:mockwatcher_with_multiple_backends) do
      mockWatcher = double(Synapse::ServiceWatcher)
      allow(mockWatcher).to receive(:name).and_return('example_service')
      backends = [{ 'host' => '10.11.11.11', 'port' => 5555, 'name' => 'somehost1'},
                  { 'host' => '10.22.22.22',   'port' => 5555, 'name' => 'somehost3'},
                  { 'host' => '10.10.10.10',   'port' => 5555, 'name' => 'somehost2'}]
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
    expect(subject.generate_backend_stanza(mockwatcher_with_cookie_value_method_hash, mockConfig)).to eql(["\nbackend example_service3", [], ["\tserver somehost:5555 somehost:5555 cookie 9e736eef2f5a1d441e34ade3d2a8eb1e3abb1c92 check inter 2000 rise 3 fall 2"]])
  end

  it 'generates backend stanza without cookies for tcp mode' do
    mockConfig = ['mode tcp']
    expect(subject.generate_backend_stanza(mockwatcher, mockConfig)).to eql(["\nbackend example_service", ["\tmode tcp"], ["\tserver somehost:5555 somehost:5555 check inter 2000 rise 3 fall 2"]])
  end

  it 'respects haproxy_server_options' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher_with_server_options, mockConfig)).to eql(["\nbackend example_service2", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 check inter 2000 rise 3 fall 2 backup"]])
  end

  it 'generates frontend stanza ' do
    mockConfig = []
    expect(subject.generate_frontend_stanza(mockwatcher_frontend, mockConfig)).to eql(["\nfrontend example_service4", [], "\tbind localhost:2200", "\tdefault_backend example_service4"])
  end

  it 'respects frontend bind_address ' do
    mockConfig = []
    expect(subject.generate_frontend_stanza(mockwatcher_frontend_with_bind_address, mockConfig)).to eql(["\nfrontend example_service5", [], "\tbind 127.0.0.3:2200", "\tdefault_backend example_service5"])
  end

end
