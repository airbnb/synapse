require 'spec_helper'
require 'synapse/service_watcher/zookeeper'
require 'synapse/service_watcher/zookeeper_dns'

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

  context 'ZookeeperWatcher' do
    let(:discovery) { { 'method' => 'zookeeper', 'hosts' => 'somehost', 'path' => 'some/path' } }
    let(:mock_zk) { double(ZK) }
    let(:mock_node) do
      node_double = double()
      allow(node_double).to receive(:first).and_return(service_data_string)
      node_double
    end

    subject { Synapse::ServiceWatcher::ZookeeperWatcher.new(config, mock_synapse) }
    it 'decodes data correctly' do
      expect(subject.send(:deserialize_service_instance, service_data_string)).to eql(deserialized_service_data)
    end

    it 'decodes config data correctly' do
      expect(subject.send(:parse_service_config, config_for_generator_string.first)).to eql(parsed_config_for_generator)
    end

    it 'decodes invalid config data correctly' do
      expect(subject.send(:parse_service_config, config_for_generator_invalid_string)).to eql(parsed_config_for_generator_invalid)
    end

    it 'handle zk get retrun nil success' do
      expect(mock_zk).to receive(:get).with('test/path', {}).and_return(nil)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_return(nil)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_return(nil)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_return(nil)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_return(mock_node)
      subject.instance_variable_set('@zk', mock_zk)
      expect(subject.send(:zk_get_path, 'test/path', :retry_limit => 5, :retry_interval => 0)).to eql mock_node
    end

    it 'handle zk get retrun nill failure' do
      expect(mock_zk).to receive(:get).with('test/path', {}).and_return(nil)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_return(nil)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_return(nil)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_return(nil)
      subject.instance_variable_set('@zk', mock_zk)
      expect{subject.send(:zk_get_path, 'test/path', :retry_interval => 0)}.to raise_error(RuntimeError)
    end

    it 'handle zk get timeout success' do
      expect(mock_zk).to receive(:get).with('test/path', {}).and_raise(ZK::Exceptions::OperationTimeOut)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_raise(ZK::Exceptions::OperationTimeOut)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_raise(ZK::Exceptions::OperationTimeOut)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_raise(ZK::Exceptions::OperationTimeOut)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_return(mock_node)
      subject.instance_variable_set('@zk', mock_zk)
      expect(subject.send(:zk_get_path, 'test/path', :retry_limit => 5, :retry_interval => 0)).to eql mock_node
    end

    it 'handle zk get timeout failure' do
      expect(mock_zk).to receive(:get).with('test/path', {}).and_raise(ZK::Exceptions::OperationTimeOut)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_raise(ZK::Exceptions::OperationTimeOut)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_raise(ZK::Exceptions::OperationTimeOut)
      expect(mock_zk).to receive(:get).with('test/path', {}).and_raise(ZK::Exceptions::OperationTimeOut)
      subject.instance_variable_set('@zk', mock_zk)
      expect{subject.send(:zk_get_path, 'test/path', :retry_interval => 0)}.to raise_error(RuntimeError)
    end

    it 'reacts to zk push events' do
      expect(subject).to receive(:watch)
      expect(subject).to receive(:discover).and_call_original
      expect(mock_zk).to receive(:get).with('some/path', {:watch=>true}).and_return(config_for_generator_string)
      expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).and_return(
        ["test_child_1"]
      )
      expect(mock_zk).to receive(:get).with('some/path/test_child_1', {}).and_return(mock_node)
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
      expect(mock_zk).to receive(:get).with('some/path/test_child_1', {}).and_raise(ZK::Exceptions::NoNode)

      subject.instance_variable_set('@zk', mock_zk)
      expect(subject).to receive(:set_backends).with([],{})
      subject.send(:watcher_callback).call
    end

    it 'responds fail to ping? when the client is not in any of the connected/connecting/associatin state' do
      expect(mock_zk).to receive(:associating?).and_return(false)
      expect(mock_zk).to receive(:connecting?).and_return(false)
      expect(mock_zk).to receive(:connected?).and_return(false)

      subject.instance_variable_set('@zk', mock_zk)
      expect(subject.ping?).to be false
    end

    context 'watcher_callback' do
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

    context "generator_config_path" do
      let(:discovery) { { 'method' => 'zookeeper', 'hosts' => 'somehost', 'path' => 'some/path', 'generator_config_path' => generator_config_path } }
      before :each do
        expect(subject).to receive(:watch)
        expect(subject).to receive(:discover).and_call_original
        expect(mock_zk).to receive(:children).with('some/path', {:watch=>true}).and_return(
          ["test_child_1"]
        )
        expect(mock_zk).to receive(:get).with('some/path/test_child_1', {}).and_raise(ZK::Exceptions::NoNode)

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
    end
  end

  context 'ZookeeperDnsWatcher' do
    let(:discovery) { { 'method' => 'zookeeper_dns', 'hosts' => 'somehost','path' => 'some/path' } }
    let(:message_queue) { [] }
    subject { Synapse::ServiceWatcher::ZookeeperDnsWatcher::Zookeeper.new(config, mock_synapse, message_queue) }
    it 'decodes data correctly' do
      expect(subject.send(:deserialize_service_instance, service_data_string)).to eql(deserialized_service_data)
    end
  end
end
