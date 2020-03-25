require 'spec_helper'
require 'synapse/config_generator/haproxy'
require 'active_support/all'
require 'active_support/testing/time_helpers'

class MockWatcher; end;

describe Synapse::ConfigGenerator::Haproxy do
  include ActiveSupport::Testing::TimeHelpers

  subject { Synapse::ConfigGenerator::Haproxy.new(config['haproxy']) }

  let (:nerve_weights_subject) {
    nerve_weights_subject = subject.clone
    nerve_weights_subject.opts['use_nerve_weights'] = true
    nerve_weights_subject
  }

  let(:maxid) do
    Synapse::ConfigGenerator::Haproxy::MAX_SERVER_ID
  end

  let(:mockwatcher) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service')
    backends = [{ 'host' => 'somehost', 'port' => 5555}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {'server_options' => "check inter 2000 rise 3 fall 2"}
    })
    allow(mockWatcher).to receive(:revision).and_return(1)
    mockWatcher
  end

  let(:mockwatcher_with_hashed_haproxy_server_options) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'haproxy_server_options' => {'option_key' => 'option_value'}}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {'server_options' => "check inter 2000 rise 3 fall 2"}
    })
    allow(mockWatcher).to receive(:revision).and_return(1)
    mockWatcher
  end

  let(:mockwatcher_with_hashed_server_options) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service2')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'haproxy_server_options' => 'id 12 backup'}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {'server_options' => {'hash_key' => 'check inter 2000 rise 3 fall 2'}}
    })
    mockWatcher
  end

  let(:mockwatcher_with_server_options) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service2')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'haproxy_server_options' => 'id 12 backup'}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {'server_options' => "check inter 2000 rise 3 fall 2"}
    })
    mockWatcher
  end

  let(:mockwatcher_with_non_haproxy_config) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service2')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'haproxy_server_options' => 'id 12 backup'}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'unknown' => {'server_options' => "check inter 2000 rise 3 fall 2"}
    })
    mockWatcher
  end

  let(:mockwatcher_with_empty_haproxy_config) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service2')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'haproxy_server_options' => 'id 12 backup'}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {}
    })
    mockWatcher
  end

  let(:mockwatcher_with_server_id) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('server_id_svc')
    backends = [
      {'host' => 'host1', 'port' => 5555, 'haproxy_server_id' => 1},
      {'host' => 'host2', 'port' => 5555},
      {'host' => 'host3', 'port' => 5555, 'haproxy_server_options' => "id #{maxid}"},
    ]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {
        'server_options' => "check inter 2000 rise 3 fall 2",
        'backend_order' => 'asc',
      },
    })
    mockWatcher
  end

  let(:mockwatcher_with_cookie_value_method_hash) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service3')
    backends = [{ 'host' => 'somehost', 'port' => 5555}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {'server_options' => "check inter 2000 rise 3 fall 2", 'cookie_value_method' => 'hash'}
    })
    mockWatcher
  end

  let(:mockwatcher_with_weight) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_weighted_service')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'weight' => 1}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {
      }
    })
    mockWatcher
  end

  let(:mockwatcher_with_weight_as_string) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_weighted_service')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'weight' => '1'}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {
      }
    })
    mockWatcher
  end

  let(:mockwatcher_with_weight_as_hash) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_weighted_service')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'weight' => {}}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {
      }
    })
    mockWatcher
  end

  let(:mockwatcher_with_haproxy_weight_and_nerve_weight) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_weighted_service')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'weight' => 99, 'haproxy_server_options' => 'weight 50'}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {
      }
    })
    mockWatcher
  end

  let(:mockwatcher_frontend) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service4')
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {'port' => 2200}
    })
    mockWatcher
  end

  let(:mockwatcher_frontend_with_bind_options) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service4')
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {
        'port' => 2200,
      'bind_options' => 'ssl no-sslv3 crt /path/to/cert/example.pem ciphers ECDHE-ECDSA-CHACHA20-POLY1305'
      }
    })
    mockWatcher
  end

  let(:mockwatcher_frontend_with_bind_address) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service5')
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {'port' => 2200, 'bind_address' => "127.0.0.3"}
    })
    mockWatcher
  end

  let(:mockwatcher_frontend_with_nil_port) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service6')
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {'port' => nil, 'bind_address' => "unix@/foo/bar.sock"}
    })
    mockWatcher
  end

  let(:mockwatcher_disabled) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('disabled_watcher')
    backends = [{ 'host' => 'somehost', 'port' => 5555}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {'port' => 2200, 'disabled' => true}
    })
    allow(mockWatcher).to receive(:revision).and_return(1)
    mockWatcher
  end

  let(:mockwatcher_with_server_option_templates) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service7')
    backends = [{ 'host' => 'somehost', 'port' => 5555, 'haproxy_server_options' => 'id 12 backup'}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return({
      'haproxy' => {'server_options' => "check port %{port} inter 2000 rise 3 fall 2"}
    })
    mockWatcher
  end

  describe '#initialize' do
    it 'succeeds on minimal config' do
      conf = {
        'global' => [],
        'defaults' => [],
        'do_writes' => false,
        'do_reloads' => false,
        'do_socket' => false
      }
      Synapse::ConfigGenerator::Haproxy.new(conf)
      expect{Synapse::ConfigGenerator::Haproxy.new(conf)}.not_to raise_error
    end

    it 'reads use_nerve_weights in config' do
      conf = {
        'global' => [],
        'defaults' => [],
        'do_writes' => false,
        'do_reloads' => false,
        'do_socket' => false,
        'use_nerve_weights' => true
      }
      expect{Synapse::ConfigGenerator::Haproxy.new(conf)}.not_to raise_error
      haproxy = Synapse::ConfigGenerator::Haproxy.new(conf)
      expect(haproxy.opts['use_nerve_weights']).to eql(true)
    end

    it 'validates req_pairs' do
      req_pairs = {
        'do_writes' => 'config_file_path',
        'do_socket' => 'socket_file_path',
        'do_reloads' => 'reload_command',
        'do_checks' => 'check_command',
      }
      valid_conf = {
        'global' => [],
        'defaults' => [],
        'do_reloads' => false,
        'do_socket' => false,
        'do_writes' => false,
        'do_checks' => false,
      }

      req_pairs.each do |key, value|
        conf = valid_conf.clone
        conf[key] = true
        expect{Synapse::ConfigGenerator::Haproxy.new(conf)}.
          to raise_error(ArgumentError, "the `#{value}` option is required when `#{key}` is true")
      end
    end

    context 'when do_checks is true' do
      let(:invalid_conf) {
        {
          'global' => [],
          'defaults' => [],
          'do_reloads' => false,
          'do_socket' => false,
          'do_writes' => false,
          'do_checks' => true,
        }
      }
      let(:conf_additions) {
        {
          'check_command' => 'haproxy -c -f /etc/haproxy/haproxy-candidate.cfg',
          'candidate_config_file_path' => '/etc/haproxy/haproxy-candidate.cfg',
        }
      }

      context 'when check parameters are not set together' do
        it 'raises an error' do
          conf_additions.each do |key, value|
            conf = invalid_conf.clone
            conf[key] = value
            expect{Synapse::ConfigGenerator::Haproxy.new(conf)}.
              to raise_error(ArgumentError)
          end
        end
      end

      context 'when check parameters are set together' do
        it 'does not raise an error' do
          conf = invalid_conf.clone
          conf_additions.each do |key, value|
            conf[key] = value
          end

          expect{Synapse::ConfigGenerator::Haproxy.new(conf)}.not_to raise_error
        end
      end
    end

    it 'properly defaults do_writes, do_socket, do_checks, do_reloads, use_nerve_weights' do
      conf = {
        'global' => [],
        'defaults' => [],
        'config_file_path' => 'test_file',
        'socket_file_path' => 'test_socket',
        'reload_command' => 'test_reload'
      }

      expect{Synapse::ConfigGenerator::Haproxy.new(conf)}.not_to raise_error
      haproxy = Synapse::ConfigGenerator::Haproxy.new(conf)
      expect(haproxy.opts['do_writes']).to eql(true)
      expect(haproxy.opts['do_socket']).to eql(true)
      expect(haproxy.opts['do_reloads']).to eql(true)
      expect(haproxy.opts['do_checks']).to eql(false)
      expect(haproxy.opts['use_nerve_weights']).to eql(nil)
    end

    it 'complains when req_pairs are not passed at all' do
      conf = {
        'global' => [],
        'defaults' => [],
      }
      expect{Synapse::ConfigGenerator::Haproxy.new(conf)}.to raise_error(ArgumentError)
    end
  end

  describe '#name' do
    it 'returns haproxy' do
      expect(subject.name).to eq('haproxy')
    end
  end

  describe 'disabled watcher' do
    let(:watchers) { [mockwatcher, mockwatcher_disabled] }
    let(:socket_file_path) { 'socket_file_path' }

    before do
      config['haproxy']['do_socket'] = true
      config['haproxy']['socket_file_path'] = socket_file_path
    end

    it 'does not generate config' do
      allow(subject).to receive(:parse_watcher_config).and_return({})
      expect(subject).to receive(:generate_frontend_stanza).exactly(:once).with(mockwatcher, nil)
      expect(subject).to receive(:generate_backend_stanza).exactly(:once).with(mockwatcher, nil)
      subject.update_config(watchers)
    end

    context 'when configuration via the socket succeeds' do
      before do
        subject.instance_variable_set(:@restart_required, false)
        allow(subject).to receive(:generate_config).exactly(:once).and_return 'mock_config'
      end

      it 'does not cause a restart due to the socket' do
        mock_socket_output = "example_service,somehost:5555,0,0,0,0,200,0,0,0,0,0,,0,0,0,0,DOWN,0,"
        allow(subject).to receive(:talk_to_socket).with(socket_file_path, "show stat\n").and_return mock_socket_output

        expect(subject).to receive(:talk_to_socket).exactly(:once).with(
          socket_file_path, "enable server example_service/somehost:5555\n"
        ).and_return "\n"

        subject.update_config(watchers)

        expect(subject.instance_variable_get(:@restart_required)).to eq false
      end

      it 'disables existing servers on the socket' do
        mock_socket_output = "example_service,somehost:5555,0,0,0,0,200,0,0,0,0,0,,0,0,0,0,DOWN,0,\ndisabled_watcher,somehost:5555,0,0,0,0,200,0,0,0,0,0,,0,0,0,0,UP,0,"
        allow(subject).to receive(:talk_to_socket).with(socket_file_path, "show stat\n").and_return mock_socket_output
        stub_const('Synapse::ConfigGenerator::Haproxy::HAPROXY_CMD_BATCH_SIZE', 1)

        expect(subject).to receive(:talk_to_socket).exactly(:once).with(
          socket_file_path, "enable server example_service/somehost:5555\n"
        ).and_return "\n"
        expect(subject).to receive(:talk_to_socket).exactly(:once).with(
          socket_file_path, "disable server disabled_watcher/somehost:5555\n"
        ).and_return "\n"

        subject.update_config(watchers)

        expect(subject.instance_variable_get(:@restart_required)).to eq false
      end
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
      before {
        config['haproxy']['do_writes'] = true
        config['haproxy']['do_checks'] = false
      }

      it 'writes the new config' do
        expect(subject).to receive(:write_config).with(new_config)
        subject.update_config(watchers)
      end

      it 'writes the new config to the file system' do
        expect(File).to receive(:read).and_return(nil)
        expect(File).to receive(:write)
        expect(FileUtils).to receive(:mv)
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

    context 'if watcher has empty or nil config_for_generator[haproxy]' do
      let(:watchers) { [mockwatcher, mockwatcher_with_non_haproxy_config, mockwatcher_with_empty_haproxy_config] }

      it 'does not generate config for those watchers' do
        allow(subject).to receive(:parse_watcher_config).and_return({})
        expect(subject).to receive(:generate_frontend_stanza).exactly(:once).with(mockwatcher, nil)
        expect(subject).to receive(:generate_backend_stanza).exactly(:once).with(mockwatcher, nil)
        subject.update_config(watchers)
      end
    end

    context 'if watcher has a new different config_for_generator[haproxy]' do
      let(:watchers) { [mockwatcher] }
      let(:socket_file_path) { ['socket_file_path1', 'socket_file_path2'] }

      before do
        config['haproxy']['do_writes'] = true
        config['haproxy']['do_reloads'] = true
        config['haproxy']['do_socket'] = true
        config['haproxy']['socket_file_path'] = socket_file_path
      end

      it 'trigger restart' do
        allow(subject).to receive(:parse_watcher_config).and_return({})
        allow(subject).to receive(:write_config).and_return(nil)

        # set config_for_generator in state_cache to {}
        allow(subject.state_cache).to receive(:config_for_generator).and_return({})

        # make sure @restart_required is not triggered in other places
        allow(subject).to receive(:update_backends_at).and_return(nil)
        allow(subject).to receive(:generate_frontend_stanza).exactly(:once).with(mockwatcher, nil).and_return([])
        allow(subject).to receive(:generate_backend_stanza).exactly(:once).with(mockwatcher, nil).and_return([])

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
    let(:watchers_with_non_haproxy_config) { [mockwatcher_with_non_haproxy_config] }
    let(:state_file_ttl) { 60 } # seconds

    before do
      config['haproxy']['state_file_path'] = '/statefile'
      config['haproxy']['state_file_ttl'] = state_file_ttl
      allow(subject.state_cache).to receive(:write_data_to_state_file)
    end

    it 'adds backends along with timestamps' do
      subject.update_state_file(watchers)

      watcher_names = watchers.map{ |w| w.name }
      expect(subject.state_cache.send(:seen).keys).to contain_exactly(*watcher_names)

      watchers.each do |watcher|
        backend_names = watcher.backends.map{ |b| subject.construct_name(b) }
        data = subject.state_cache.backends(watcher.name)
        expect(data.keys).to contain_exactly(*backend_names)

        backend_names.each do |backend_name|
          expect(data[backend_name]).to include('timestamp')
        end
      end
    end

    it 'adds config_for_generator from watcher' do
      subject.update_state_file(watchers)

      watcher_names = watchers.map{ |w| w.name }
      expect(subject.state_cache.send(:seen).keys).to contain_exactly(*watcher_names)

      watchers.each do |watcher|
        watcher_config_for_generator = watcher.config_for_generator
        data = subject.state_cache.config_for_generator(watcher.name)
        expect(data).to eq(watcher_config_for_generator["haproxy"])
      end
    end

    it 'does not add config_for_generator of other generators from watcher' do
      subject.update_state_file(watchers_with_non_haproxy_config)

      watcher_names = watchers_with_non_haproxy_config.map{ |w| w.name }
      expect(subject.state_cache.send(:seen).keys).to contain_exactly(*watcher_names)

      watchers_with_non_haproxy_config.each do |watcher|
        watcher_config_for_generator = watcher.config_for_generator
        data = subject.state_cache.config_for_generator(watcher.name)
        expect(data).to eq({})
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
        end.to_not change { subject.state_cache.send(:seen) }
      end

      context 'if those backends are stale' do
        it 'removes those backends' do
          travel_to Time.now
          subject.update_state_file(watchers)

          watchers.each do |watcher|
            allow(watcher).to receive(:backends).and_return([])
          end

          # the final +1 puts us over the expiry limit
          travel_to (Time.now + state_file_ttl + 1)
          subject.update_state_file(watchers)
          watchers.each do |watcher|
            data = subject.state_cache.backends(watcher.name)
            expect(data).to be_empty
          end
        end
      end
    end
  end

  it 'generates backend stanza' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher, mockConfig)).to eql(["\nbackend example_service", [], ["\tserver somehost:5555 somehost:5555 id 1 cookie somehost:5555 check inter 2000 rise 3 fall 2"]])
  end

  it 'ignores non-strings of haproxy_server_options' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher_with_hashed_haproxy_server_options, mockConfig)).to eql(["\nbackend example_service", [], ["\tserver somehost:5555 somehost:5555 id 1 cookie somehost:5555 check inter 2000 rise 3 fall 2"]])
  end

  it 'ignores non-strings of server_options' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher_with_hashed_server_options, mockConfig)).to eql(["\nbackend example_service2", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 id 12 backup"]])
  end

  describe 'when known backend gets offline' do
    let(:mockStateCache) do
      mockCache = double(Synapse::ConfigGenerator::Haproxy::HaproxyState)
      allow(mockCache).to receive(:backends).with(mockwatcher.name).and_return(
        {
          "somehost2:5555" => {
            "host" => "somehost2",
            "port" => 5555,
            'haproxy_server_id' => 10,
          }
        }
      )
      mockCache
    end

    before do
      allow(mockwatcher).to receive(:config_for_generator).and_return(
        {
          'haproxy' => {
            'server_options' => "check inter 2000 rise 3 fall 2",
            'backend_order' => 'no_shuffle',
          }
        }
      )
      subject.instance_variable_set(:@state_cache, mockStateCache)
    end

    it 'generates backend stanza with the disabled stat' do
      mockConfig = ['mode tcp']
      expect(subject.generate_backend_stanza(mockwatcher, mockConfig)).to eql(
        [
          "\nbackend example_service",
          ["\tmode tcp"],
          [
            "\tserver somehost2:5555 somehost2:5555 id 10 check inter 2000 rise 3 fall 2 disabled",
            "\tserver somehost:5555 somehost:5555 id 1 check inter 2000 rise 3 fall 2"
          ]
        ]
      )
    end
  end

  describe 'generate backend stanza in correct order' do
    let(:multiple_backends_stanza_map) do
      {
        'asc' => [
          "\nbackend example_service",
          [],
          ["\tserver somehost1_10.11.11.11:5555 10.11.11.11:5555 id 1 cookie somehost1_10.11.11.11:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost2_10.10.10.10:5555 10.10.10.10:5555 id 3 cookie somehost2_10.10.10.10:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost3_10.22.22.22:5555 10.22.22.22:5555 id 2 cookie somehost3_10.22.22.22:5555 check inter 2000 rise 3 fall 2"
          ]
        ],
        'desc' => [
          "\nbackend example_service",
          [],
          ["\tserver somehost3_10.22.22.22:5555 10.22.22.22:5555 id 2 cookie somehost3_10.22.22.22:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost2_10.10.10.10:5555 10.10.10.10:5555 id 3 cookie somehost2_10.10.10.10:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost1_10.11.11.11:5555 10.11.11.11:5555 id 1 cookie somehost1_10.11.11.11:5555 check inter 2000 rise 3 fall 2"
          ]
        ],
        'no_shuffle' => [
          "\nbackend example_service",
          [],
          ["\tserver somehost1_10.11.11.11:5555 10.11.11.11:5555 id 1 cookie somehost1_10.11.11.11:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost3_10.22.22.22:5555 10.22.22.22:5555 id 2 cookie somehost3_10.22.22.22:5555 check inter 2000 rise 3 fall 2",
           "\tserver somehost2_10.10.10.10:5555 10.10.10.10:5555 id 3 cookie somehost2_10.10.10.10:5555 check inter 2000 rise 3 fall 2"
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
          allow(mockwatcher_with_multiple_backends).to receive(:config_for_generator).and_return({
            'haproxy' => {
              'server_options' => "check inter 2000 rise 3 fall 2",
              'backend_order' => order_option
            }
          })
          expect(subject.generate_backend_stanza(mockwatcher_with_multiple_backends, mockConfig)).to eql(multiple_backends_stanza_map[order_option])
        end
      end
    end

    context "when shuffle is specified for backend_order" do
      it 'generates backend stanza in reproducible order' do
        mockConfig = []
        allow(mockwatcher_with_multiple_backends).to receive(:config_for_generator).and_return({
          'haproxy' => {
            'server_options' => "check inter 2000 rise 3 fall 2",
            'backend_order' => 'shuffle',
            'server_order_seed' => 1234,
          }
        })
        runs = (1..5).collect { |_| subject.generate_backend_stanza(mockwatcher_with_multiple_backends, mockConfig) }
        expect(runs.length).to eq(5)
        expect(runs.uniq.length).to eq(1)
      end
    end
  end

  it 'hashes backend name as cookie value' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher_with_cookie_value_method_hash, mockConfig)).to eql(["\nbackend example_service3", [], ["\tserver somehost:5555 somehost:5555 id 1 cookie 9e736eef2f5a1d441e34ade3d2a8eb1e3abb1c92 check inter 2000 rise 3 fall 2"]])
  end

  it 'generates backend stanza without cookies for tcp mode' do
    mockConfig = ['mode tcp']
    expect(subject.generate_backend_stanza(mockwatcher, mockConfig)).to eql(["\nbackend example_service", ["\tmode tcp"], ["\tserver somehost:5555 somehost:5555 id 1 check inter 2000 rise 3 fall 2"]])
  end

  it 'respects haproxy_server_options' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher_with_server_options, mockConfig)).to eql(["\nbackend example_service2", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 check inter 2000 rise 3 fall 2 id 12 backup"]])
  end

  it 'templates haproxy backend options' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher_with_server_option_templates, mockConfig)).to eql(["\nbackend example_service7", [], ["\tserver somehost:5555 somehost:5555 cookie somehost:5555 check port 5555 inter 2000 rise 3 fall 2 id 12 backup"]])
  end

  it 'respects haproxy_server_id' do
    mockConfig = []
    expect(subject.generate_backend_stanza(mockwatcher_with_server_id, mockConfig)).to eql(
      ["\nbackend server_id_svc", [],
        [
          "\tserver host1:5555 host1:5555 id 1 cookie host1:5555 check inter 2000 rise 3 fall 2",
          "\tserver host2:5555 host2:5555 id 2 cookie host2:5555 check inter 2000 rise 3 fall 2",
          "\tserver host3:5555 host3:5555 cookie host3:5555 check inter 2000 rise 3 fall 2 id #{maxid}",
        ]
      ]
    )
  end

  describe '#use_nerve_weights' do
    it 'respects weight as integer' do
      mockConfig = []
      expect(nerve_weights_subject.generate_backend_stanza(mockwatcher_with_weight, mockConfig)).to eql(
        ["\nbackend example_weighted_service", [], ["\tserver somehost:5555 somehost:5555 id 1 cookie somehost:5555 weight 1"]]
        )
    end

    it 'ignores weight if not valid' do
      mockConfig = []
      expect(nerve_weights_subject.generate_backend_stanza(mockwatcher_with_weight_as_hash, mockConfig)).to eql(
        ["\nbackend example_weighted_service", [], ["\tserver somehost:5555 somehost:5555 id 1 cookie somehost:5555"]]
        )
    end

    it 'ignores haproxy_server_options weight with use_nerve_weights true' do
      mockConfig = []
      expect(nerve_weights_subject.generate_backend_stanza(mockwatcher_with_haproxy_weight_and_nerve_weight, mockConfig)).to eql(
        ["\nbackend example_weighted_service", [], ["\tserver somehost:5555 somehost:5555 id 1 cookie somehost:5555 weight 99"]]
        )
    end

    it 'ignores nerve weight with use_nerve_weights false' do
      mockConfig = []
      expect(subject.generate_backend_stanza(mockwatcher_with_haproxy_weight_and_nerve_weight, mockConfig)).to eql(
        ["\nbackend example_weighted_service", [], ["\tserver somehost:5555 somehost:5555 id 1 cookie somehost:5555 weight 50"]]
        )
    end
  end

  describe '#write_config' do
    before {
      config['haproxy']['config_file_path'] = 'config_file'
      config['haproxy']['candidate_config_file_path'] = 'candidate_config_file'

      allow(File).to receive(:read).with('config_file').and_return('haproxy-config')
      allow(File).to receive(:read).with('candidate_config_file').and_return('candidate-haproxy-config')
    }

    context 'when candidate_config_file_path is not set' do
      before {
        config['haproxy'].delete('candidate_config_file_path')
        config['haproxy']['do_checks'] = false
      }

      it 'still succeeds' do
        allow(FileUtils).to receive(:mv)

        expect(File).to receive(:write).with('config_file.tmp', 'new-config')
        expect{subject.write_config('new-config')}.not_to raise_error
      end
    end

    context 'when config changes' do
      it 'writes candidate config' do
        allow(FileUtils).to receive(:mv)
        allow(subject).to receive(:check_config?).and_return(true)

        expect(File).to receive(:write).with('candidate_config_file', 'new-config')
        subject.write_config('new-config')
      end

      it 'checks config command' do
        allow(FileUtils).to receive(:mv)
        allow(File).to receive(:write).with('candidate_config_file', 'new-config')

        expect(subject).to receive(:check_config?).and_return(true)
        subject.write_config('new-config')
      end

      context 'when config file does not exist' do
        before {
          allow(File).to receive(:read).with('config_file').and_raise(Errno::ENOENT)
          allow(subject).to receive(:check_config?).and_return(true)
        }

        it 'writes the new config' do
          expect(File).to receive(:write).with('candidate_config_file', 'haproxy-config')
          expect(FileUtils).to receive(:mv).with('candidate_config_file', 'config_file')
          expect(subject.write_config('haproxy-config')).to eq(true)
        end
      end

      context 'when config check succeeds' do
        before {
          expect(subject).to receive(:check_config?).and_return(true)
        }

        it 'moves the candidate file to normal location' do
          allow(File).to receive(:write).with('candidate_config_file', 'new-config')
          expect(FileUtils).to receive(:mv).with('candidate_config_file', 'config_file')
          expect(subject.write_config('new-config')).to eq(true)
        end
      end

      context 'when config check fails' do
        before {
          expect(subject).to receive(:check_config?).and_return(false)
          allow(File).to receive(:write).with('candidate_config_file', 'new-config')
        }

        it 'does not move the candidate file to production location' do
          expect(FileUtils).not_to receive(:mv)
          expect(subject.write_config('new-config')).to eq(false)
        end
      end
    end

    context 'when config does not change' do
      it 'returns false' do
        expect(subject.write_config('haproxy-config')).to eq(false)
      end

      it 'does not write the candidate config' do
        expect(File).not_to receive(:write)
        subject.write_config('haproxy-config')
      end

      it 'does not move the candidate file' do
        expect(FileUtils).not_to receive(:mv)
        subject.write_config('haproxy-config')
      end

      it 'does not check config command' do
        expect(subject).not_to receive(:check_config?)
        subject.write_config('haproxy-config')
      end
    end
  end

  describe '#check_config?' do
    let(:exit_success) { double }
    let(:exit_fail) { double }

    before {
      allow(exit_success).to receive(:success?).and_return(true)
      allow(exit_success).to receive(:exitstatus).and_return(0)

      allow(exit_fail).to receive(:success?).and_return(false)
      allow(exit_fail).to receive(:exitstatus).and_return(1)

      config['haproxy']['do_checks'] = true
      config['haproxy']['check_command'] = 'haproxy_check_mock'
      config['haproxy']['candidate_config_file_path'] = 'candidate-haproxy-config-file'
    }

    it 'calls the supplied command' do
      expect(Open3).to receive(:capture2e).with("haproxy_check_mock").and_return(["success", exit_success])
      subject.check_config?
    end

    context 'when check command succeeds' do
      before {
        expect(Open3).to receive(:capture2e).and_return(["haproxy check succeeded", exit_success])
      }

      it 'returns true' do
        expect(subject.check_config?).to eq(true)
      end
    end

    context 'when check command fails' do
      before {
        expect(Open3).to receive(:capture2e).and_return(["haproxy check failed", exit_fail])
      }

      it 'returns true' do
        expect(subject.check_config?).to eq(false)
      end
    end

    context 'when do_checks is false' do
      before {
        config['haproxy']['do_checks'] = false
      }

      it 'always returns true' do
        expect(subject.check_config?).to eq(true)
      end

      it 'does not call command' do
        expect(Open3).not_to receive(:capture2e)
        subject.check_config?
      end
    end
  end

  it 'generates frontend stanza ' do
    mockConfig = []
    expect(subject.generate_frontend_stanza(mockwatcher_frontend, mockConfig)).to eql(["\nfrontend example_service4", [], "\tbind localhost:2200", "\tdefault_backend example_service4"])
  end

  it 'generates frontend stanza with bind options ' do
    mockConfig = []
    expect(subject.generate_frontend_stanza(mockwatcher_frontend_with_bind_options, mockConfig)).to eql(["\nfrontend example_service4", [], "\tbind localhost:2200 ssl no-sslv3 crt /path/to/cert/example.pem ciphers ECDHE-ECDSA-CHACHA20-POLY1305", "\tdefault_backend example_service4"])
  end

  it 'generates frontend stanza with nil port' do
    mockConfig= []
    expect(subject.generate_frontend_stanza(mockwatcher_frontend_with_nil_port, mockConfig)).to eql(["\nfrontend example_service6", [], "\tbind unix@/foo/bar.sock", "\tdefault_backend example_service6"])
  end

  it 'respects frontend bind_address ' do
    mockConfig = []
    expect(subject.generate_frontend_stanza(mockwatcher_frontend_with_bind_address, mockConfig)).to eql(["\nfrontend example_service5", [], "\tbind 127.0.0.3:2200", "\tdefault_backend example_service5"])
  end

end
