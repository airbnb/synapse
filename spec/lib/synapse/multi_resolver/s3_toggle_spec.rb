require 'spec_helper'
require 'synapse/service_watcher/multi/resolver/s3_toggle'
require 'synapse/service_watcher/base/base'
require 'active_support/all'
require 'active_support/testing/time_helpers'

describe Synapse::ServiceWatcher::Resolver::S3ToggleResolver do
  include ActiveSupport::Testing::TimeHelpers

  let(:watchers) { {'primary' => primary_watcher, 'secondary' => secondary_watcher} }

  let(:primary_watcher) {
    w = double(Synapse::ServiceWatcher::BaseWatcher)
    allow(w).to receive(:backends).and_return(primary_backends)
    allow(w).to receive(:ping?).and_return(true)
    w
  }
  let(:primary_backends) { ["primary_1", "primary_2", "primary_3"] }

  let(:secondary_watcher) {
    w = double(Synapse::ServiceWatcher::BaseWatcher)
    allow(w).to receive(:backends).and_return(secondary_backends)
    allow(w).to receive(:ping?).and_return(true)
    w
  }
  let(:secondary_backends) { ["secondary_1", "secondary_2", "secondary_3"] }

  let(:opts) { opts_valid }
  let(:opts_valid) {
    {'method' => 's3_toggle',
     's3_url' => 's3://config_bucket/path1/path2',
     's3_polling_interval_seconds' => 60}
  }

  subject { Synapse::ServiceWatcher::Resolver::S3ToggleResolver.new(opts, watchers, -> {}) }

  describe '#initialize' do
    it 'constructs normally' do
      expect { subject }.not_to raise_error
    end

    it 'creates an S3BackgroundPoller' do
      Synapse::ServiceWatcher::Resolver::S3ToggleResolver.class_variable_set(:@@s3_watcher, nil)
      expect(Synapse::ServiceWatcher::Resolver::S3ToggleResolver::BackgroundS3Poller).to receive(:new).exactly(:once)
      subject
    end

    context 'with invalid arguments' do
      context 'with invalid method' do
        let(:opts) { opts_valid.merge({'method' => 'bogus'}) }

        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end

      context 'with invalid s3_url' do
        let(:opts) { opts_valid.merge({'s3_url' => 'bogus'}) }

        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end

      context 'with invalid s3_polling_interval_seconds' do
        let(:opts) { opts_valid.merge({'s3_polling_interval_seconds' => 'bogus'}) }

        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end

      %w(method s3_url s3_polling_interval_seconds).each do |opt|
        context "missing #{opt}" do
          let(:opts) {
            opts_valid.delete(opt)
            opts_valid
          }

          it 'raises an error' do
            expect { subject }.to raise_error(ArgumentError)
          end
        end
      end

      context 'without watchers' do
        let(:watchers) { [] }
        it 'raises an error' do
          expect { subject }.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe '#start' do
    let(:background_poller) { double("BackgroundS3Poller") }

    before :each do
      Synapse::ServiceWatcher::Resolver::S3ToggleResolver.class_variable_set(:@@s3_watcher, background_poller)
    end

    it 'adds s3 file to the background poller' do
      expect(background_poller)
        .to receive(:add_path)
        .exactly(:once)
        .with('config_bucket', 'path1/path2', 60, duck_type(:call))

      subject.start
    end
  end

  describe '#stop' do
    let(:background_poller) { double("BackgroundS3Poller") }

    before :each do
      Synapse::ServiceWatcher::Resolver::S3ToggleResolver.class_variable_set(:@@s3_watcher, background_poller)
    end

    it 'calls stop on background poller' do
      expect(background_poller).to receive(:stop).exactly(:once)
      subject.stop
    end
  end

  describe '#merged_backends' do
    before :each do
      subject.instance_variable_set(:@watcher_setting, 'secondary')
    end

    it 'calls #backends on current watcher' do
      expect(secondary_watcher).to receive(:backends).exactly(:once)
      subject.merged_backends
    end

    it 'does not call #backends on other watchers' do
      expect(primary_watcher).not_to receive(:backends)
      subject.merged_backends
    end

    it 'returns backends from current watcher' do
      expect(subject.merged_backends).to eq(secondary_backends)
    end
  end

  describe '#healthy?' do
    before :each do
      subject.instance_variable_set(:@watcher_setting, 'secondary')
    end

    it 'calls #ping? on current watcher' do
      expect(secondary_watcher).to receive(:ping?).exactly(:once)
      subject.healthy?
    end

    it 'does not call #ping? on other watchers' do
      expect(primary_watcher).not_to receive(:ping?)
      subject.healthy?
    end

    context 'when current watcher returns true' do
      before :each do
        allow(secondary_watcher).to receive(:ping?).and_return(true)
      end

      it 'returns true' do
        expect(subject.healthy?).to eq(true)
      end
    end

    context 'when current watcher returns false' do
      before :each do
        allow(secondary_watcher).to receive(:ping?).and_return(false)
      end

      it 'returns false' do
        expect(subject.healthy?).to eq(false)
      end
    end

    context 'when other watchers return unhealthy' do
      before :each do
        allow(secondary_watcher).to receive(:ping?).and_return(true)
        allow(primary_watcher).to receive(:ping?).and_return(false)
      end

      it 'still returns true' do
        expect(subject.healthy?).to eq(true)
      end
    end
  end

  describe 'set_watcher' do
    before :each do
      subject.instance_variable_set(:@watcher_setting, 'primary')
    end

    it 'sends a notification' do
      expect(subject).to receive(:send_notification).exactly(:once)
      subject.send(:set_watcher, 'secondary')
    end

    it 'sets @watcher_setting' do
      subject.send(:set_watcher, 'secondary')
      expect(subject.instance_variable_get(:@watcher_setting)).to eq('secondary')
    end

    context 'with same watcher' do
      it 'does not send a notification' do
        expect(subject).not_to receive(:send_notification)
        subject.send(:set_watcher, 'primary')
      end
    end

    context 'with unknown watchers' do
      it 'does not change @watcher_setting' do
        expect { subject.send(:set_watcher, 'bogus-watcher') }
          .not_to change { subject.instance_variable_get(:@watcher_setting) }
      end

      it 'does not send a notification' do
        expect(subject).not_to receive(:send_notification)
        subject.send(:set_watcher, 'bogus-watcher')
      end
    end
  end

  describe Synapse::ServiceWatcher::Resolver::S3ToggleResolver::BackgroundS3Poller do
    subject { Synapse::ServiceWatcher::Resolver::S3ToggleResolver::BackgroundS3Poller.new }

    let(:interval) { 60 }
    let(:last_run) { Time.now - interval - 1 }
    let(:mock_callback) { -> (path){} }
    let(:path_data) {
      {:bucket => 'bucket', :key => 'key', :polling_interval => interval,
       :last_run => last_run, :picked_watcher => nil, :last_content_hash => nil,
       :callbacks => [ mock_callback ]}
    }

    describe '#add_path' do
      it 'calls start' do
        expect(subject).to receive(:start).exactly(:once)
        subject.add_path('bucket', 'key', interval, mock_callback)
      end

      context 'with a new path' do
        it 'adds it to @paths' do
          subject.add_path('bucket', 'key', interval, mock_callback)

          path_data[:last_run] = instance_of(Time)
          expect(subject.instance_variable_get(:@paths).values).to match([path_data])
        end
      end

      context 'with an existing path' do
        before :each do
          subject.add_path('bucket', 'key', interval, mock_callback)
        end

        context 'with same interval' do
          it 'does not change @paths' do
            expect { subject.add_path('bucket', 'key', interval, mock_callback) }
              .not_to change { subject.instance_variable_get(:@paths).length }
          end

          it 'adds a new callback' do
            expect { subject.add_path('bucket', 'key', interval, mock_callback) }
              .to change { subject.instance_variable_get(:@paths).values[0][:callbacks].length }
              .by(1)
          end
        end

        context 'with new interval' do
          it 'adds it to @paths' do
            expect { subject.add_path('bucket', 'key', interval + 1, mock_callback) }
              .to change { subject.instance_variable_get(:@paths).length }
              .by(1)
          end
        end
      end
    end

    describe '#start' do
      it 'increments a counter' do
        allow(Thread).to receive(:new)
        expect { subject.start }
          .to change { subject.instance_variable_get(:@callback_count) }
          .by(1)
      end

      it 'starts a thread' do
        expect(Thread).to receive(:new).exactly(:once)
        subject.start
      end

      context 'when a thread already exists' do
        let(:thread) { double(Thread) }

        before :each do
          subject.instance_variable_set(:@thread, thread)
        end

        it 'continues silently' do
          expect(Thread).not_to receive(:new)
          expect { subject.start }.not_to raise_error
        end
      end
    end

    describe '#stop' do
     let(:thread) { double(Thread) }
      before :each do
        subject.instance_variable_set(:@thread, thread)
      end

      it 'increments a counter' do
        allow(thread).to receive(:join)
        expect { subject.stop }
          .to change { subject.instance_variable_get(:@stop_count) }
          .by(1)
      end

      context 'when all started paths are stopped' do
        it 'stops the thread' do
          expect(thread).to receive(:join).exactly(:once)
          subject.instance_variable_set(:@callback_count, 5)

          (1..5).each do
            subject.stop
          end
        end
      end

      context 'when only some started paths are stopped' do
        it 'does not stop the thread' do
          expect(thread).not_to receive(:join)
          subject.instance_variable_set(:@callback_count, 5)

          (1..3).each do
            subject.stop
          end
        end
      end

      context 'when thread does not exist' do
        let(:thread) { nil }
        it 'continues silently' do
          expect { subject.stop }.not_to raise_error
        end
      end
    end

    describe 'update_s3_picks' do
      let(:last_run) {
        travel_to Time.now
        Time.now
      }
      let(:paths_key) { "bucket-key:#{interval}s" }
      let(:s3_data) { {'primary' => 50, 'secondary' => 50} }

      before :each do
        subject.instance_variable_set(:@paths, {paths_key => path_data})
      end

      context 'when path is out of date' do
        let(:last_run) {
          travel_to Time.now
          Time.now - interval - 1
        }

        it 'reads from s3' do
          expect(subject).to receive(:read_s3_file).exactly(:once).with('bucket', 'key')
          subject.send(:update_s3_picks)
        end

        it 'calls set_watcher' do
          allow(subject).to receive(:read_s3_file).and_return(s3_data)
          expect(subject).to receive(:set_watcher).exactly(:once).with(path_data, s3_data)
          subject.send(:update_s3_picks)
        end

        it 'sets path data properly' do
          allow(subject).to receive(:read_s3_file).and_return(s3_data)
          subject.send(:update_s3_picks)

          path_data[:last_content_hash] = anything
          expect(subject.instance_variable_get(:@paths)[paths_key]).to match(path_data)
        end
      end

      context 'when path is up to date' do
        it 'does not read from s3' do
          expect(subject).not_to receive(:read_s3_file)
          subject.send(:update_s3_picks)
        end

        it 'does not call set_watcher' do
          expect(subject).not_to receive(:set_watcher)
          subject.send(:update_s3_picks)
        end

        it 'does not change path data' do
          expect { subject.send(:update_s3_picks) }
            .not_to change { subject.instance_variable_get(:@paths)[paths_key] }
        end
      end

      context 'with no paths' do
        before :each do
          subject.instance_variable_set(:@paths, {paths_key => path_data})
        end

        it 'continues silently' do
          expect { subject.send(:update_s3_picks) }.not_to raise_error
        end
      end
    end

    describe 'pick_watcher' do
      let(:watcher_weights) { {'primary' => 0, 'secondary' => 100} }

      it 'picks between the watchers by weight' do
        distribution = {'primary' => 25, 'secondary' => 75}
        results = {}
        distribution.each_key do |k|
          results[k] = 0
        end

        (0..100).each do
          choice = subject.send(:pick_watcher, distribution)
          results[choice] += 1
        end

        # check distribution of results instead of actual choices
        expect(results['primary']).to be > 0
        expect(results['secondary']).to be > 0
        expect(results['secondary']).to be > results['primary']
      end

      context 'when primary has all weight' do
        let(:watcher_weights) { {'primary' => 100, 'secondary' => 0} }

        it 'returns primary' do
          expect(subject.send(:pick_watcher, watcher_weights)).to eq('primary')
        end
      end

      context 'when weights are empty' do
        let(:watcher_weights) { {} }

        it 'returns nil' do
          expect(subject.send(:pick_watcher, watcher_weights)).to eq(nil)
        end
      end

      context 'when weights are nil' do
        let(:watcher_weights) { nil }

        it 'returns nil' do
          expect(subject.send(:pick_watcher, watcher_weights).nil?).to eq(true)
        end
      end

      context 'when weights add up to more than 100' do
        let(:watcher_weights) { {'primary' => 50, 'secondary' => 100} }

        it 'still sets watcher properly' do
          results = {}
          watcher_weights.each_key do |k|
            results[k] = 0
          end

          (0..100).each do
            choice = subject.send(:pick_watcher, watcher_weights)
            results[choice] += 1
          end

          # check distribution of results instead of actual choices
          expect(results['primary']).to be > 0
          expect(results['secondary']).to be > 0
          expect(results['secondary']).to be > results['primary']
        end
      end

      context 'when weights are the same' do
        let(:watcher_weights) { {'primary' => 50, 'secondary' => 50} }

        it 'picks each watcher equally' do
          distribution = {'primary' => 50, 'secondary' => 50}
          results = {}
          distribution.each_key do |k|
            results[k] = 0
          end

          (0..1000).each do
            choice = subject.send(:pick_watcher, distribution)
            results[choice] += 1
          end

          # check distribution of results instead of actual choices
          expect(results['primary']).to be > 0
          expect(results['secondary']).to be > 0
          expect(results['secondary']).to be_within(100).of(results['primary'])
        end
      end

      context 'when weights add up to 0' do
        let(:watcher_weights) { {'primary' => 0, 'secondary' => 0} }

        it 'returns nil' do
          expect(subject.send(:pick_watcher, watcher_weights).nil?).to eq(true)
        end
      end
    end

    describe 'set_watcher' do
      let(:watcher_weights) { {'primary' => 0, 'secondary' => 100} }

      it 'sets :picked_watcher' do
        subject.send(:set_watcher,  path_data, watcher_weights)
        expect(path_data[:picked_watcher]).to eq('secondary')
      end

      it 'calls pick_watcher' do
        expect(subject).to receive(:pick_watcher).with(watcher_weights).exactly(:once)
        subject.send(:set_watcher, path_data, watcher_weights)
      end

      it 'sends a notification' do
        expect(mock_callback).to receive(:call).exactly(:once).with('secondary')
        subject.send(:set_watcher, path_data, watcher_weights)
      end

      context 'with multiple callbacks' do
        it 'calls each one' do
          mock_callback2 = -> {}
          path_data[:callbacks] << mock_callback2
          expect(mock_callback).to receive(:call).exactly(:once).with('secondary')
          expect(mock_callback2).to receive(:call).exactly(:once).with('secondary')

          subject.send(:set_watcher, path_data, watcher_weights)
        end
      end

      context 'when called multiple times' do
        it 'deterministically picks the same watcher' do
          expect(subject)
            .to receive(:pick_watcher)
            .with(watcher_weights)
            .exactly(:once)
            .and_call_original

          subject.send(:set_watcher, path_data, watcher_weights)

          # Explicitly set the setting to something that cannot occur.
          # However, it should not change because the weights do not change.
          path_data[:picked_watcher] = 'mock-watcher'
          expect(subject.send(:set_watcher, path_data, watcher_weights)).to eq('mock-watcher')
        end

        it 'only sends one notification' do
          expect(mock_callback).to receive(:call).exactly(:once)

          subject.send(:set_watcher, path_data, watcher_weights)
          subject.send(:set_watcher, path_data, watcher_weights)
        end
      end

      context 'with different weights' do
        let(:watcher_weights) { {'primary' => 100, 'secondary' => 0} }
        let(:watcher_weights_new) { {'primary' => 0, 'secondary' => 100} }

        it 'picks a new watcher' do
          expect(subject)
            .to receive(:pick_watcher)
            .with(watcher_weights)
            .exactly(:once)
            .and_call_original

          expect(subject)
            .to receive(:pick_watcher)
            .with(watcher_weights_new)
            .exactly(:once)
            .and_call_original

          expect(subject.send(:set_watcher, path_data, watcher_weights)).to eq('primary')
          expect(subject.send(:set_watcher, path_data, watcher_weights_new)).to eq('secondary')
        end

        it 'sends a notification' do
          expect(mock_callback).to receive(:call).exactly(:twice)

          subject.send(:set_watcher, path_data, watcher_weights)
          subject.send(:set_watcher, path_data, watcher_weights_new)
        end
      end

      context 'when pick_watcher returns nil' do
        before :each do
          allow(subject).to receive(:pick_watcher).and_return(nil)
          path_data[:picked_watcher] = 'mock-watcher'
        end

        it 'does not change the watcher' do
          expect(subject.send(:set_watcher, path_data, watcher_weights)).to eq('mock-watcher')
          expect(path_data[:picked_watcher]).to eq('mock-watcher')
        end

        it 'does not send a notification' do
          expect(mock_callback).not_to receive(:call)
          subject.send(:set_watcher, path_data, watcher_weights)
        end
      end
    end

    describe 'read_s3_file' do
      let(:s3_data) { {'primary' => 50, 'secondary' => 50} }
      let(:s3_data_string) { YAML.dump(s3_data) }
      let(:s3_bucket) { 'config_bucket' }
      let(:s3_path) { 'path1/path2' }
      let(:mock_s3_response) {
        mock_response = double("mock_s3_response")
        allow(mock_response).to receive(:data).and_return({:data => s3_data_string})
        mock_response
      }

      let(:mock_s3) {
        mock_s3 = double(AWS::S3::Client)
        Synapse::ServiceWatcher::Resolver::S3ToggleResolver::BackgroundS3Poller.class_variable_set(:@@s3_client, mock_s3)
        mock_s3
      }

      it 'properly parses response' do
        allow(mock_s3).to receive(:get_object).and_return(mock_s3_response)
        expect(subject.send(:read_s3_file, s3_bucket, s3_path)).to eq(s3_data)
      end

      context 'with yaml comments' do
        let(:s3_data_string) { "---\n# example comment\nprimary: 50\nsecondary: 50" }

        it 'properly parses response' do
          allow(mock_s3).to receive(:get_object).and_return(mock_s3_response)
          expect(subject.send(:read_s3_file, s3_bucket, s3_path)).to eq(s3_data)
        end
      end

      it 'calls S3 API with proper bucket and key' do
        expect(mock_s3)
          .to receive(:get_object)
          .with(bucket_name: s3_bucket, key: s3_path)
          .exactly(:once)
          .and_return(mock_s3_response)

        subject.send(:read_s3_file, s3_bucket, s3_path)
      end

      context 'with s3 errors' do
        it 'returns an empty configuration' do
          expect(mock_s3).to receive(:get_object).and_raise(AWS::S3::Errors::NoSuchBucket)
          expect(subject.send(:read_s3_file, s3_bucket, s3_path)).to eq(nil)
        end
      end

      context 'with invalid yaml' do
        let(:s3_data_string) { "{" }

        it 'returns an empty configuration' do
          allow(mock_s3).to receive(:get_object).and_return(mock_s3_response)
          expect(subject.send(:read_s3_file, s3_bucket, s3_path)).to eq(nil)
        end
      end

      context 'with invalid schema' do
        let(:s3_data) { {"watchers" => [{"bogus" => 10}, {"morebogus" => 11}]} }

        it 'returns an empty configuration' do
          allow(mock_s3).to receive(:get_object).and_return(mock_s3_response)
          expect(subject.send(:read_s3_file, s3_bucket, s3_path)).to eq(nil)
        end
      end
    end

    describe 'validate_s3_file_schema' do
      context 'with invalid schema' do
        let(:schema) { {"watchers" => [{"bogus" => 10}, {"morebogus" => 11}]} }

        it 'returns false' do
          expect(subject.send(:validate_s3_file_schema, schema)).to eq(false)
        end
      end

      context 'with invalid type' do
        let(:schema) { "bogus" }

        it 'returns false' do
          expect(subject.send(:validate_s3_file_schema, schema)).to eq(false)
        end
      end

      context 'with nil contents' do
        let(:schema) { nil }

        it 'returns false' do
          expect(subject.send(:validate_s3_file_schema, schema)).to eq(false)
        end
      end

      context 'with floating-point weights' do
        let(:schema) { {"primary" => 0.25, "secondary" => 0.75} }

        it 'returns false' do
          expect(subject.send(:validate_s3_file_schema, schema)).to eq(false)
        end
      end

      context 'with valid schema' do
        let(:schema) { {'primary' => 50, 'secondary' => 50} }

        it 'returns true' do
          expect(subject.send(:validate_s3_file_schema, schema)).to eq(true)
        end
      end
    end
  end

  describe 'parse_s3_url' do
    let(:s3_url) { 's3://my_bucket/object_path/child' }

    it 'returns components' do
      expect(subject.send(:parse_s3_url, s3_url)).to eq({'bucket' => 'my_bucket', 'path' => 'object_path/child'})
    end

    context 'without s3 prefix' do
      let(:s3_url) { 'my_bucket/object_path/child' }

      it 'raises an error' do
        expect { subject.send(:parse_s3_url, s3_url) }.to raise_error(ArgumentError)
      end
    end

    context 'without components' do
      let(:s3_url) { 's3://' }

      it 'raises an error' do
        expect { subject.send(:parse_s3_url, s3_url) }.to raise_error(ArgumentError)
      end
    end

    context 'without path' do
      let(:s3_url) { 's3://my_bucket' }

      it 'raises an error' do
        expect { subject.send(:parse_s3_url, s3_url) }.to raise_error(ArgumentError)
      end
    end
  end
end
