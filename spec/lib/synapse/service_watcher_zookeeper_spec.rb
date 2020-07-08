require 'spec_helper'
require 'active_support/all'
require 'active_support/testing/time_helpers'

require 'synapse/service_watcher/zookeeper/zookeeper'
require 'synapse/service_watcher/zookeeper_poll/zookeeper_poll'
require 'synapse/service_watcher/zookeeper_dns/zookeeper_dns'
require 'synapse/service_watcher/zookeeper_dns_poll/zookeeper_dns_poll'

describe Synapse::ServiceWatcher::ZookeeperWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end
  let(:config) do
    {
      'name' => 'test',
      'haproxy' => {},
      'discovery' => discovery,
    }
  end

  let(:service_data) do
    {
      'host' => 'server',
      'port' => '8888',
      'name' => 'server',
      'weight' => '1',
      'haproxy_server_options' => 'backup',
      'labels' => { 'az' => 'us-east-1a' }
    }
  end
  let(:config_for_generator_haproxy) do
    {
      "frontend" => [
        "binding ::1:1111"
      ],
      "listen" => [
        "mode http",
        "option httpchk GET /health",
        "timeout  client  300s",
        "timeout  server  300s",
        "option httplog"
      ],
      "port" => 1111,
      "server_options" => "check inter 60s fastinter 2s downinter 5s rise 3 fall 2",
    }
  end
  let(:config_for_generator) do
    {
      "haproxy" => config_for_generator_haproxy,
      "unknown_generator" => {
        "key" => "value"
      }
    }
  end
  let(:config_for_generator_invalid) do
    {
      "haproxy" => "value",
    }
  end
  let(:service_data_string) { service_data.to_json }
  let(:deserialized_service_data) {
    service_data
  }
  let(:config_for_generator_string) { [config_for_generator.to_json] }
  let(:parsed_config_for_generator) do
    {
      "haproxy" => config_for_generator_haproxy
    }
  end
  let(:config_for_generator_invalid_string) { config_for_generator_invalid.to_json }
  let(:parsed_config_for_generator_invalid) do
    {
      "haproxy" => {}
    }
  end

  describe 'ZookeeperWatcher' do
    let(:discovery) { { 'method' => 'zookeeper', 'hosts' => ['somehost'], 'path' => 'some/path' } }
    let(:mock_zk) { double(ZK) }
    let(:mock_node) do
      node_double = double()
      allow(node_double).to receive(:first).and_return(service_data_string)
      node_double
    end

    subject { Synapse::ServiceWatcher::ZookeeperWatcher.new(config, mock_synapse, ->(*args) {}) }
    it 'decodes data correctly' do
      expect(subject.send(:deserialize_service_instance, service_data_string)).to eql(deserialized_service_data)
    end

    it 'decodes config data correctly' do
      expect(subject.send(:parse_service_config, config_for_generator_string.first)).to eql(parsed_config_for_generator)
    end

    it 'decodes invalid config data correctly' do
      expect(subject.send(:parse_service_config, config_for_generator_invalid_string)).to eql(parsed_config_for_generator_invalid)
    end

    context 'with unknown fields' do
      let(:service_data) {
        {
          'host' => 'server',
          'port' => '8888',
          'name' => 'server',
          'weight' => '1',
          'haproxy_server_options' => 'backup',
          'labels' => { 'az' => 'us-east-1a' },
          'skipGc' => true,
        }
      }

      let(:backend) {
        {
          'name' => 'server',
          'host' => 'server',
          'port' => '8888',
          'labels' => {
            'az' => 'us-east-1a'
          },
          'weight' => '1',
          'haproxy_server_options' => 'backup',
          'id' => 5
        }
      }

      it 'decodes properly' do
        deserialized = subject.send(:deserialize_service_instance, service_data_string)
        expect(deserialized).to eq(deserialized_service_data)
        expect(subject.send(:create_backend_info, 'i-xxxxxxx_0000000005', deserialized)).to eq(backend)
      end
    end

    it 'reacts to zk push events' do
      expect(subject).to receive(:watch)
      expect(subject).to receive(:discover).and_call_original
      expect(mock_zk).to receive(:get).with('some/path', {:watch=>true}).and_return(config_for_generator_string)
      expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).and_return(
        ["test_child_1"]
      )
      expect(mock_zk).to receive(:get).with('some/path/test_child_1').and_return(mock_node)
      subject.instance_variable_set('@zk', mock_zk)
      expect(subject).to receive(:set_backends).with([service_data.merge({'id' => 1})], parsed_config_for_generator)
      subject.send(:watcher_callback).call
    end

    it 'handles zk consistency issues' do
      expect(subject).to receive(:watch)
      expect(subject).to receive(:discover).and_call_original
      expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).and_return(
        ["test_child_1"]
      )
      expect(mock_zk).to receive(:get).with('some/path', {:watch=>true}).and_return("")
      expect(mock_zk).to receive(:get).with('some/path/test_child_1').and_raise(ZK::Exceptions::NoNode)

      subject.instance_variable_set('@zk', mock_zk)
      expect(subject).to receive(:set_backends).with([],{})
      subject.send(:watcher_callback).call
    end

    describe 'watcher_callback' do
      before :each do
        subject.instance_variable_set(:@retry_policy, {'max_attempts' => 2, 'base_interval' => 0, 'max_interval' => 0})
      end

      it 'with retriable error retries until succeeded' do
        expect(mock_zk).to receive(:register)
        expect(mock_zk).to receive(:exists?).with('some/path', {:watch=>true}).once.and_raise(ZK::Exceptions::ConnectionLoss)
        expect(mock_zk).to receive(:exists?).with('some/path', {:watch=>true}).once.and_return(true)
        expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).once.and_raise(ZK::Exceptions::OperationTimeOut)
        expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).once.and_return(["test_child_1"])
        expect(mock_zk).to receive(:get).with('some/path', {:watch=>true}).once.and_raise(::Zookeeper::Exceptions::ContinuationTimeoutError)
        expect(mock_zk).to receive(:get).with('some/path', {:watch=>true}).once.and_return(config_for_generator_string)
        expect(mock_zk).to receive(:get).with('some/path/test_child_1').once.and_raise(::Zookeeper::Exceptions::NotConnected)
        expect(mock_zk).to receive(:get).with('some/path/test_child_1').once.and_return(mock_node)
        expect(subject).to receive(:set_backends).with([service_data.merge({'id' => 1})], parsed_config_for_generator)
        subject.instance_variable_set('@zk', mock_zk)
        subject.send(:watcher_callback).call
      end

      it 'exists fails with retriable error retries until failed' do
        expect(mock_zk).to receive(:register)
        expect(mock_zk).to receive(:exists?).with('some/path', {:watch=>true}).exactly(2).and_raise(ZK::Exceptions::ConnectionLoss)
        subject.instance_variable_set('@zk', mock_zk)
        expect { subject.send(:watcher_callback).call }.to raise_error(ZK::Exceptions::ConnectionLoss)
      end

      it 'children fails with retriable error retries until failed' do
        expect(mock_zk).to receive(:register)
        expect(mock_zk).to receive(:exists?).with('some/path', {:watch=>true}).once.and_return(true)
        expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).exactly(2).and_raise(ZK::Exceptions::OperationTimeOut)
        subject.instance_variable_set('@zk', mock_zk)
        expect { subject.send(:watcher_callback).call }.to raise_error(ZK::Exceptions::OperationTimeOut)
      end

      it 'get fails with retriable error retries until failed' do
        expect(mock_zk).to receive(:register)
        expect(mock_zk).to receive(:exists?).with('some/path', {:watch=>true}).once.and_return(true)
        expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).once.and_return(["test_child_1"])
        expect(mock_zk).to receive(:get).with('some/path/test_child_1').exactly(2).and_raise(::Zookeeper::Exceptions::NotConnected)
        subject.instance_variable_set('@zk', mock_zk)
        expect { subject.send(:watcher_callback).call }.to raise_error(::Zookeeper::Exceptions::NotConnected)
      end
    end

    describe 'start' do
      before :each do
        discovery['hosts'] = ['127.0.0.1:2181']
        subject.instance_variable_set(:@retry_policy, {'max_attempts' => 2, 'base_interval' => 0, 'max_interval' => 0})
        Synapse::ServiceWatcher::ZookeeperWatcher.class_variable_set(:@@zk_pool, {})
      end

      describe 'zk_connect' do
        it 'new fails with retriable error retries until succeeded' do
          expect(ZK).to receive(:new).and_raise(RuntimeError)
          expect(ZK).to receive(:new).and_return(mock_zk)
          expect(mock_zk).to receive(:on_expired_session)

          calls = 0
          subject.send(:zk_connect) {
            calls += 1
          }
          expect(calls).to eq(1)
          expect(subject.instance_variable_get(:@zk)).to eq(mock_zk)
        end

        it 'new fails with retriable error retries until failed' do
          expect(ZK).to receive(:new).exactly(2).and_raise(RuntimeError)
          expect { subject.send(:zk_connect) }.to raise_error(RuntimeError)
        end
      end

      describe 'start_discovery' do
        before :each do
          subject.instance_variable_set(:@zk, mock_zk)
        end

        it 'exists fails with retriable error retries until failed' do
          expect(mock_zk).to receive(:exists?).with('some/path').exactly(2).and_raise(ZK::Exceptions::OperationTimeOut)
          expect { subject.send(:start_discovery) }.to raise_error(ZK::Exceptions::OperationTimeOut)
        end

        it 'create fails with retriable error retires until failed' do
          expect(mock_zk).to receive(:exists?).with('some/path').exactly(2).and_return(false)
          expect(mock_zk).to receive(:exists?).with('some').exactly(2).and_return(true)
          expect(mock_zk).to receive(:create).with('some/path', {:ignore=>:node_exists}).exactly(2).and_raise(ZK::Exceptions::OperationTimeOut)
          expect { subject.send(:start_discovery) }.to raise_error(ZK::Exceptions::OperationTimeOut)
        end

        it 'calls watcher_callback' do
          allow(mock_zk).to receive(:exists?).and_return(true)
          allow(subject).to receive(:watch)
          allow(subject).to receive(:discover)

          cb = subject.send(:watcher_callback)
          expect(cb).to receive(:call).exactly(:once)

          subject.send(:start_discovery)
        end
      end

      it 'calls zk_connect' do
        expect(subject).to receive(:zk_connect).exactly(:once)
        subject.start
      end
    end

    describe 'stop' do
      it 'sets watcher to nil' do
        expect(subject.instance_variable_get(:@watcher)).to eq(nil)
        subject.stop
      end

      it 'unsubscribes from the watcher' do
        watcher = double("watcher")
        subject.instance_variable_set(:@watcher, watcher)

        expect(watcher).to receive(:unsubscribe).exactly(:once)
        subject.stop
      end
    end

    describe 'zk_connect' do
      before :each do
        Synapse::ServiceWatcher::ZookeeperWatcher.class_variable_set(:@@zk_pool, {})
      end

      it 'calls provided block' do
        allow(ZK).to receive(:new).and_return(mock_zk)
        allow(mock_zk).to receive(:on_expired_session)
        allow(mock_zk).to receive(:exists?).and_return(true)
        allow(subject).to receive(:watch)
        allow(subject).to receive(:discover)

        expect { |b| subject.send(:zk_connect, &b) }.to yield_control
      end
    end

    describe 'zk_teardown' do
      it 'calls provided block' do
        expect { |b| subject.send(:zk_teardown, &b) }.to yield_control
      end
    end

    it 'responds fail to ping? when the client is not in any of the connected/connecting/associatin state' do
      expect(mock_zk).to receive(:associating?).and_return(false)
      expect(mock_zk).to receive(:connecting?).and_return(false)
      expect(mock_zk).to receive(:connected?).and_return(false)

      subject.instance_variable_set('@zk', mock_zk)
      expect(subject.ping?).to be false
    end

    describe 'watcher_callback' do
      let (:time_now) { Time.now }
      before :each do
        expect(subject).to receive(:watch)
        expect(subject).to receive(:discover)
        subject.instance_variable_set(:@watcher, instance_double(ZK::EventHandlerSubscription))
        discovery['discovery_jitter'] = 25
        allow(Time).to receive(:now).and_return(time_now)
      end

      it 'does not sleep if there was no discovery in last discovery_jitter seconds' do
        subject.instance_variable_set(:@last_discovery, time_now - (discovery['discovery_jitter'] + 1))
        expect(subject).not_to receive(:sleep)
        subject.send(:watcher_callback).call
      end

      it 'does not sleep if @last_discovery is not set - first time' do
        expect(subject).not_to receive(:sleep)
        subject.send(:watcher_callback).call
      end

      it 'sleep if there was a discovery in last discovery_jitter seconds' do
        subject.instance_variable_set(:@last_discovery, time_now - (discovery['discovery_jitter'] - 1))
        expect(subject).to receive(:sleep).with(discovery['discovery_jitter'])
        subject.send(:watcher_callback).call
      end

      it 'do not throttle on invalid discovery_jitter' do
        discovery['discovery_jitter'] = Synapse::ServiceWatcher::ZookeeperWatcher::MAX_JITTER + 1
        expect(subject).not_to receive(:sleep)
        subject.send(:watcher_callback).call
      end
    end

    describe "generator_config_path" do
      let(:discovery) { { 'method' => 'zookeeper', 'hosts' => ['somehost'], 'path' => 'some/path', 'generator_config_path' => generator_config_path } }
      before :each do
        expect(subject).to receive(:watch)
        expect(subject).to receive(:discover).and_call_original
        expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).and_return(
          ["test_child_1"]
        )
        expect(mock_zk).to receive(:get).with('some/path/test_child_1').and_raise(ZK::Exceptions::NoNode)

        subject.instance_variable_set('@zk', mock_zk)
        expect(subject).to receive(:set_backends).with([],{})
      end

      context 'when generator_config_path is defined' do
        let(:generator_config_path) { 'some/other/path' }
        it 'reads from generator_config_path znode' do
          expect(mock_zk).to receive(:get).with(generator_config_path, {:watch=>true}).and_return("")

          subject.send(:watcher_callback).call
        end

        it 'does not crash if there is no zk node' do
          expect(mock_zk).to receive(:get).with(generator_config_path, {:watch=>true}).and_raise(ZK::Exceptions::NoNode)

          subject.send(:watcher_callback).call
        end
      end
      context 'when generator_config_path is disabled' do
        let(:generator_config_path) { 'disabled' }
        it 'does not read from any znode' do
            subject.send(:watcher_callback).call
        end
      end
    end

    context "use_path_encoding" do
      it 'parse base64 encoded prefix' do
        node = {
          'host' => '127.0.0.1',
          'port' => '3000',
          'labels' => {
            'region' => 'us-east-1',
            'az' => 'us-east-1a'
          }
        }
        encoded_str = Base64.urlsafe_encode64(JSON(node))
        child_name = "base64_#{encoded_str.length}_#{encoded_str}_0000000003"
        expect(subject.send(:parse_base64_encoded_prefix, child_name)).to eql(node)
      end

      it 'parse based64 encoded prefix without labels' do
        node = {
          'host' => '127.0.0.1',
          'port' => '3000',
        }
        encoded_str = Base64.urlsafe_encode64(JSON(node))
        child_name = "base64_#{encoded_str.length}_#{encoded_str}_0000000005"
        expect(subject.send(:parse_base64_encoded_prefix, child_name)).to eql(node)
      end

      it 'parse base64 encoded prefix returns nil' do
        expect(subject.send(:parse_base64_encoded_prefix, "i-xxxxxxx_0000000005")).to be nil
      end

      it 'parse numeric id suffix' do
        expect(subject.send(:parse_numeric_id_suffix, "i-xxxxxxx_0000000005")).to be 5
      end

      it 'parse numeric id suffix returns nil' do
        expect(subject.send(:parse_numeric_id_suffix, "i-xxxxxxx_60da")).to be nil
      end

      it 'parse backend returns correct data with fixed schema' do
        node = {
          'name' => 'i-xxxxxxx',
          'host' => '127.0.0.1',
          'port' => '3000',
          'labels' => {
            'region' => 'us-east-1',
            'az' => 'us-east-1a'
          }
        }
        backend = {
          'name' => 'i-xxxxxxx',
          'host' => '127.0.0.1',
          'port' => '3000',
          'labels' => {
            'region' => 'us-east-1',
            'az' => 'us-east-1a'
          },
          'weight' => nil,
          'haproxy_server_options' => nil,
          'id' => 5
        }
        expect(subject.send(:create_backend_info, "i-xxxxxxx_0000000005", node)).to eq backend
      end
    end

    describe "discover" do
      let(:service_data) {
        {
          'name' => 'i-testhost',
          'host' => '127.0.0.1',
          'port' => '3001',
          'labels' => {
            'region' => 'us-east-1',
            'az' => 'us-east-1a'
          }
        }
      }
      let(:backend) {
        service_data.merge({"id" => kind_of(Numeric), "weight" => nil, "haproxy_server_options" => nil})
      }

      let(:encoded_str) { Base64.urlsafe_encode64(JSON(service_data)) }
      let(:child_name) { "base64_#{encoded_str.length}_#{encoded_str}_0000000003" }

      let(:raise_no_node) { false }
      before :each do
        if raise_no_node
          expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).and_raise(ZK::Exceptions::NoNode)
          expect(mock_zk).to receive(:get).with('some/path', {:watch=>true}).and_raise(ZK::Exceptions::NoNode)
        else
          expect(mock_zk).to receive(:get).with('some/path', {:watch=>true}).and_return(config_for_generator_string)
          expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).and_return(
                               [ child_name ])
        end

        subject.instance_variable_set('@zk', mock_zk)
      end

      context "with path encoding" do
        context "with sequential node" do
          it "does not call get on child" do
            expect(mock_zk).not_to receive(:get).with(start_with("some/path/"))
            subject.send(:discover)
          end

          it 'sets backends with the parsed data' do
            expect(subject).to receive(:set_backends).exactly(:once).with([backend], parsed_config_for_generator)
            subject.send(:discover)
          end
        end

        context "with non-sequential node" do
          let(:child_name) { "base64_#{encoded_str.length}_#{encoded_str}" }

          it "does not call get on child" do
            expect(mock_zk).not_to receive(:get).with(start_with("some/path/"))
            subject.send(:discover)
          end

          it 'sets backends with the parsed data' do
            expect(subject).to receive(:set_backends).exactly(:once).with(
                                 [backend.merge({"id" => nil})], parsed_config_for_generator)
            subject.send(:discover)
          end
        end
      end

      context "without path encoding" do
        let(:child_name) { "child_1" }

        it "sets backends with the fetched data" do
          expect(mock_zk).to receive(:get).with("some/path/child_1").and_return(mock_node)
          expect(subject).to receive(:set_backends).exactly(:once).with([backend], parsed_config_for_generator)
          subject.send(:discover)
        end
      end

      context 'when parent path does not exist' do
        let(:raise_no_node) { true }

        it 'does not raise an error' do
          expect(subject).to receive(:set_backends).exactly(:once).with([], {})
          expect { subject.send(:discover) }.not_to raise_error
        end
      end
    end
  end

  describe Synapse::ServiceWatcher::ZookeeperPollWatcher do
    let(:mock_zk) {
      zk = double("zookeeper")
      allow(zk).to receive(:on_expired_session)
      zk
    }
    let(:mock_thread) { double("thread") }
    let(:discovery) { { 'method' => 'zookeeper_poll', 'hosts' => ['somehost'],'path' => 'some/path', 'polling_interval_sec' => 30 } }

    subject { Synapse::ServiceWatcher::ZookeeperPollWatcher.new(config, mock_synapse, ->(*args) {}) }

    before :each do
      # reset the pool so that doubles are not re-used across instances
      Synapse::ServiceWatcher::ZookeeperPollWatcher.class_variable_set(:@@zk_pool, {})
    end

    describe "#initialize" do
      context 'without polling_interval_sec' do
        let(:discovery) { { 'method' => 'zookeeper_poll', 'hosts' => ['somehost'], 'path' => 'some/path'} }

        it 'sets a default' do
          expect { subject }.not_to raise_error
          expect(subject.instance_variable_get(:@poll_interval).nil?).to be(false)
        end
      end

      context 'with discovery type != zookeeper_poll' do
        let(:discovery) { { 'method' => 'bogus', 'hosts' => ['somehost'],'path' => 'some/path', 'polling_interval_sec' => 30 } }

        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end

      context 'with invalid discovery duration' do
        let(:discovery) { { 'method' => 'zookeeper_poll', 'hosts' => ['somehost'],'path' => 'some/path', 'polling_interval_sec' => 'bogus' } }

        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end

      context 'with float discovery duration' do
        let(:discovery) { { 'method' => 'zookeeper_poll', 'hosts' => ['somehost'],'path' => 'some/path', 'polling_interval_sec' => 2.5 } }

        it 'constructs properly' do
          expect { subject }.not_to raise_error
        end
      end

      context 'without zookeeper hosts' do
        let(:discovery) { { 'method' => 'zookeeper_poll', 'path' => 'some/path', 'polling_interval_sec' => 'bogus' } }

        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end

      context 'without path set' do
        let(:discovery) { { 'method' => 'zookeeper_poll', 'hosts' => ['somehost'], 'polling_interval_sec' => 'bogus' } }

        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#start' do
      it 'starts a thread' do
        expect(Thread).to receive(:new)
        allow(ZK).to receive(:new).and_return(mock_zk)
        subject.start
      end

      it 'connects to zookeeper' do
        allow(Thread).to receive(:new)
        expect(ZK)
          .to receive(:new)
          .exactly(:once)
          .with('somehost', :timeout => 5, :receive_timeout_msec => 18000, :thread => :per_callback)
          .and_return(mock_zk)

        subject.start
      end

      it 'does not call create' do
        allow(Thread).to receive(:new)
        allow(ZK).to receive(:new).and_return(mock_zk)

        expect(mock_zk).not_to receive(:create)
        subject.start
      end
    end

    describe '#stop' do
      context 'when connected to zookeeper' do
        before :each do
          subject.instance_variable_set(:@thread, mock_thread.as_null_object)
          allow(mock_zk).to receive(:connecting?).and_return(false)
          allow(mock_zk).to receive(:connected?).and_return(true)
        end

        it 'disconnects' do
          allow(ZK).to receive(:new).and_return(mock_zk)
          allow(Thread).to receive(:new)

          expect(mock_zk).to receive(:close!).exactly(:once)
          subject.start
          subject.stop
        end
      end

      context 'when not connected to zookeeper' do
        it 'continues silently' do
          subject.stop
        end
      end

      context 'when thread is running' do
        before :each do
          subject.instance_variable_set(:@thread, mock_thread)
          subject.instance_variable_set(:@zk, mock_zk.as_null_object)
        end

        it 'kills the thread' do
          expect(mock_thread).to receive(:join).exactly(:once)
          subject.stop
        end
      end

      context 'when thread is not running' do
        before :each do
          subject.instance_variable_set(:@zk, mock_zk.as_null_object)
        end

        it 'continues silently' do
          expect { subject.stop }.not_to raise_error
        end
      end
    end

    describe '#ping' do
      before :each do
        subject.instance_variable_set(:@zk, mock_zk)
        allow(mock_zk).to receive(:connecting?).and_return(false)
        allow(mock_zk).to receive(:associating?).and_return(false)
        allow(mock_zk).to receive(:connected?).and_return(false)
      end

      it 'checks zookeeper' do
        expect(mock_zk).to receive(:connecting?)
        expect(mock_zk).to receive(:associating?)
        expect(mock_zk).to receive(:connected?)

        subject.ping?
      end

      context 'when zookeeper is disconnected' do
        it 'fails' do
          expect(subject.ping?).to eq(false)
        end
      end

      context 'when zookeeper is connecting' do
        it 'succeeds' do
          allow(mock_zk).to receive(:connecting?).and_return(true)
          expect(subject.ping?).to eq(true)
        end
      end

      context 'when zookeeper is connected' do
        it 'succeeds' do
          allow(mock_zk).to receive(:connected?).and_return(true)
          expect(subject.ping?).to eq(true)
        end
      end

      context 'when zookeeper is associating' do
        it 'succeeds' do
          allow(mock_zk).to receive(:associating?).and_return(true)
          expect(subject.ping?).to eq(true)
        end
      end
    end

    describe '#discover' do
      let(:raise_no_node) { false }
      before :each do
        subject.instance_variable_set(:@zk, mock_zk)

        if raise_no_node
          allow(mock_zk).to receive(:children).with('some/path', {}).and_raise(ZK::Exceptions::NoNode)
          allow(mock_zk).to receive(:get).with('some/path', {}).and_raise(ZK::Exceptions::NoNode)
        else
          allow(mock_zk).to receive(:children).with("some/path", {}).and_return([child_name])
          allow(mock_zk).to receive(:get).with("some/path", {}).and_return(config_for_generator_string)
        end
      end

      let(:service_data) {
        {
          'name' => 'i-testhost',
          'host' => '127.0.0.1',
          'port' => '3001',
          'labels' => {
            'region' => 'us-east-1',
            'az' => 'us-east-1a'
          }
        }
      }
      let(:mock_node) do
        node_double = double()
        allow(node_double).to receive(:first).and_return(service_data_string)
        node_double
      end

      let(:backend) {
        service_data.merge({"id" => kind_of(Numeric), "weight" => nil, "haproxy_server_options" => nil})
      }

      let(:encoded_str) { Base64.urlsafe_encode64(JSON(service_data)) }
      let(:child_name) { "base64_#{encoded_str.length}_#{encoded_str}_0000000003" }

      context "with path encoding" do
        context "with sequential node" do
          it "does not call get on child" do
            expect(mock_zk).not_to receive(:get).with(start_with("some/path/"))
            subject.send(:discover)
          end

          it 'sets backends with the parsed data' do
            expect(subject).to receive(:set_backends).exactly(:once).with([backend], parsed_config_for_generator)
            subject.send(:discover)
          end
        end

        context "with non-sequential node" do
          let(:child_name) { "base64_#{encoded_str.length}_#{encoded_str}" }

          it "does not call get on child" do
            expect(mock_zk).not_to receive(:get).with(start_with("some/path/"))
            subject.send(:discover)
          end

          it 'sets backends with the parsed data' do
            expect(subject).to receive(:set_backends).exactly(:once).with(
                                 [backend.merge({"id" => nil})], parsed_config_for_generator)
            subject.send(:discover)
          end
        end
      end

      context "without path encoding" do
        let(:child_name) { "child_1" }

        it "sets backends with the fetched data" do
          expect(mock_zk).to receive(:get).with("some/path/child_1").and_return(mock_node)
          expect(subject).to receive(:set_backends).exactly(:once).with([backend], parsed_config_for_generator)
          subject.send(:discover)
        end
      end

      context 'when parent path does not exist' do
        let (:raise_no_node) { true }

        it 'does not raise an error' do
          expect(subject).to receive(:set_backends).exactly(:once).with([], {})
          expect { subject.send(:discover) }.not_to raise_error
        end
      end

      describe "retry_policy" do
        before :each do
          subject.instance_variable_set(:@retry_policy, {'max_attempts' => 2, 'base_interval' => 0, 'max_interval' => 0})
        end

        context 'with retriable errors' do
          before :each do
            allow(mock_zk).to receive(:register)
            allow(mock_zk).to receive(:exists?).with('some/path', {:watch=>true}).once.and_raise(ZK::Exceptions::ConnectionLoss)
            allow(mock_zk).to receive(:exists?).with('some/path', {:watch=>true}).once.and_return(true)
            allow(mock_zk).to receive(:children).with('some/path', {:watch=>true}).once.and_raise(ZK::Exceptions::OperationTimeOut)
            allow(mock_zk).to receive(:children).with('some/path', {:watch=>true}).once.and_return(["test_child_1"])
            allow(mock_zk).to receive(:get).with('some/path', {:watch=>true}).once.and_raise(::Zookeeper::Exceptions::ContinuationTimeoutError)
            allow(mock_zk).to receive(:get).with('some/path', {:watch=>true}).once.and_return(config_for_generator_string)
            allow(mock_zk).to receive(:get).with('some/path/test_child_1').once.and_raise(::Zookeeper::Exceptions::NotConnected)
            allow(mock_zk).to receive(:get).with('some/path/test_child_1').once.and_return(mock_node)
            subject.instance_variable_set('@zk', mock_zk)
          end

          it 'retries until success' do
            expect { subject.send(:discover) }.not_to raise_error
          end

          it 'calls set_backends' do
            expect(subject)
              .to receive(:set_backends)
              .with([service_data.merge({'id' => kind_of(Numeric), 'haproxy_server_options' => nil, "weight" => nil})],
                    parsed_config_for_generator)
            subject.send(:discover)
          end
        end
      end
    end
  end

  describe 'ZookeeperDnsWatcher' do
    let(:discovery) { { 'method' => 'zookeeper_dns', 'hosts' => ['somehost'],'path' => 'some/path' } }

    subject { Synapse::ServiceWatcher::ZookeeperDnsWatcher.new(config, mock_synapse, ->(*args) {}) }
    let(:mock_zk) { double(Synapse::ServiceWatcher::ZookeeperWatcher) }
    let(:mock_dns) { double(Synapse::ServiceWatcher::ZookeeperDnsWatcher::Dns) }

    context 'with base watcher options' do
      let(:use_previous_backends) { double('bool') }
      let(:config) {
        {
          'name' => 'test',
          'haproxy' => {},
          'discovery' => discovery,
          'use_previous_backends' => use_previous_backends,
        }
      }

      it 'passes all options to children watchers' do
        expect(Synapse::ServiceWatcher::ZookeeperWatcher).to receive(:new).exactly(:once).with({'name' => 'test', 'discovery' => {'hosts' => discovery['hosts'], 'path' => discovery['path'], 'method' => 'zookeeper'}, 'default_servers' => [], 'use_previous_backends' => use_previous_backends}, anything, anything).and_return(mock_zk)
        expect(Synapse::ServiceWatcher::ZookeeperDnsWatcher::Dns).to receive(:new).exactly(:once).with({'name' => 'test', 'discovery' => {}, 'default_servers' => [], 'use_previous_backends' => use_previous_backends}, anything, anything, anything, anything).and_return(mock_dns)
        expect(mock_zk).to receive(:start).exactly(:once)
        expect(mock_dns).to receive(:start).exactly(:once)
        expect(Thread).to receive(:new).exactly(:once)

        subject.start
      end
    end

    describe 'make_zookeeper_watcher' do
      let(:mock_queue) { double(Queue) }
      let(:backends) { [{'name' => 'host-1', 'port' => 1234}, {'name' => 'host-2', 'port' => 5678}] }

      it 'creates a ZK watcher' do
        expect(subject.send(:make_zookeeper_watcher, mock_queue)).to be_kind_of(Synapse::ServiceWatcher::ZookeeperWatcher)
      end

      it 'creates a ZK watcher with proper reconfigure' do
        zk = subject.send(:make_zookeeper_watcher, mock_queue)

        expect(mock_queue).to receive(:push).with(Synapse::ServiceWatcher::ZookeeperDnsWatcher::Messages::NewServers.new(backends)).exactly(:once)
        expect(subject).to receive(:reconfigure!).exactly(:once)

        zk.send(:set_backends, backends)
      end
    end
  end

  describe 'ZookeeperDnsPollWatcher' do
    let(:discovery) { { 'method' => 'zookeeper_dns_poll', 'hosts' => ['somehost'], 'path' => 'some/path' } }

    subject { Synapse::ServiceWatcher::ZookeeperDnsPollWatcher.new(config, mock_synapse, ->(*args) {}) }
    let(:mock_zk) { double(Synapse::ServiceWatcher::ZookeeperPollWatcher) }
    let(:mock_dns) { double(Synapse::ServiceWatcher::ZookeeperDnsWatcher::Dns) }

        context 'with base watcher options' do
      let(:use_previous_backends) { double('bool') }
      let(:config) {
        {
          'name' => 'test',
          'haproxy' => {},
          'discovery' => discovery,
          'use_previous_backends' => use_previous_backends,
        }
      }

      it 'passes all options to children watchers' do
        expect(Synapse::ServiceWatcher::ZookeeperPollWatcher).to receive(:new).exactly(:once).with({'name' => 'test', 'discovery' => {'hosts' => discovery['hosts'], 'path' => discovery['path'], 'method' => 'zookeeper_poll'}, 'default_servers' => [], 'use_previous_backends' => use_previous_backends}, anything, anything).and_return(mock_zk)
        expect(Synapse::ServiceWatcher::ZookeeperDnsWatcher::Dns).to receive(:new).exactly(:once).with({'name' => 'test', 'discovery' => {}, 'default_servers' => [], 'use_previous_backends' => use_previous_backends}, anything, anything, anything, anything).and_return(mock_dns)
        expect(mock_zk).to receive(:start).exactly(:once)
        expect(mock_dns).to receive(:start).exactly(:once)
        expect(Thread).to receive(:new).exactly(:once)

        subject.start
      end
    end

    describe 'make_zookeeper_watcher' do
      let(:mock_queue) { double(Queue) }
      let(:backends) { [{'name' => 'host-1', 'port' => 1234}, {'name' => 'host-2', 'port' => 5678}] }

      it 'creates a ZK watcher' do
        expect(subject.send(:make_zookeeper_watcher, mock_queue)).to be_kind_of(Synapse::ServiceWatcher::ZookeeperPollWatcher)
      end

      it 'creates a ZK watcher with proper reconfigure' do
        zk = subject.send(:make_zookeeper_watcher, mock_queue)

        expect(mock_queue).to receive(:push).with(Synapse::ServiceWatcher::ZookeeperDnsWatcher::Messages::NewServers.new(backends)).exactly(:once)
        expect(subject).to receive(:reconfigure!).exactly(:once)

        zk.send(:set_backends, backends)
      end
    end
  end
end
