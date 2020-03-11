require 'spec_helper'
require 'synapse/service_watcher/multi/resolver/s3_toggle'
require 'synapse/service_watcher/base/base'

describe Synapse::ServiceWatcher::Resolver::S3ToggleResolver do
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

  subject { Synapse::ServiceWatcher::Resolver::S3ToggleResolver.new(opts, watchers) }

  describe '#initialize' do
    context 'with valid arguments' do
      it 'constructs normally' do
        expect { subject }.not_to raise_error
      end
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
    it 'starts a thread' do
      expect(Thread).to receive(:new).exactly(:once)
      subject.start
    end
  end

  describe '#stop' do
    context 'with a thread running' do
      let(:mock_thread) { double(Thread) }

      it 'waits to exit' do
        subject.instance_variable_set(:@thread, mock_thread)
        expect(mock_thread).to receive(:join).exactly(:once)
        subject.stop
      end
    end

    context 'without a thread running' do
      it 'continues silently' do
        subject.stop
      end
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
        distribution = {'primary' => 50, 'secondary' => 150}
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
    end

    context 'with unknown watcher' do
      let(:watcher_weights) { {'primary' => 0, 'secondary' => 1, 'bogus' => 100000} }

      it 'ignores unknown watchers' do
        (0..100).each do
          expect(subject.send(:pick_watcher, watcher_weights)).to eq('secondary')
        end
      end
    end

    context 'with only unknown watchers' do
      let(:watcher_weights) { {'bogus' => 10000} }

      it 'does not pick' do
        (0..100).each do
          expect(subject.send(:pick_watcher, watcher_weights)).to eq(nil)
        end
      end
    end
  end

  describe 'set_watcher' do
    let(:watcher_weights) { {'primary' => 50, 'secondary' => 50} }

    it 'sets @watcher_setting' do
      subject.send(:set_watcher, {'primary' => 0, 'secondary' => 100})
      expect(subject.instance_variable_get(:@watcher_setting)).to eq('secondary')
    end

    it 'calls set_watcher' do
      expect(subject).to receive(:pick_watcher).with(watcher_weights).exactly(:once)
      subject.send(:set_watcher, watcher_weights)
    end

    context 'when called multiple times' do
      it 'deterministically picks the same watcher' do
        expect(subject).to receive(:pick_watcher).with(watcher_weights).exactly(:once).and_call_original

        subject.send(:set_watcher, watcher_weights)

        # Explicitly set the setting to something that cannot occur.
        # However, it should not change because the weights do not change.
        subject.instance_variable_set(:@watcher_setting, 'mock-watcher')
        expect(subject.send(:set_watcher, watcher_weights)).to eq('mock-watcher')
      end
    end

    context 'with different weights' do
      let(:watcher_weights) { {'primary' => 100, 'secondary' => 0} }
      let(:watcher_weights_new) { {'primary' => 0, 'secondary' => 100} }

      it 'picks a new watcher' do
        expect(subject).to receive(:pick_watcher).with(watcher_weights).exactly(:once).and_call_original
        expect(subject).to receive(:pick_watcher).with(watcher_weights_new).exactly(:once).and_call_original

        expect(subject.send(:set_watcher, watcher_weights)).to eq('primary')
        expect(subject.send(:set_watcher, watcher_weights_new)).to eq('secondary')
      end
    end

    context 'when pick_watcher returns nil' do
      it 'does not change the watcher' do
        allow(subject).to receive(:pick_watcher).and_return(nil)

        subject.instance_variable_set(:@watcher_setting, 'mock-watcher')
        expect(subject.send(:set_watcher, watcher_weights)).to eq('mock-watcher')
      end
    end
  end

  describe 'read_s3_file' do
    let(:s3_data) { {'primary' => 50, 'secondary' => 50} }
    let(:s3_data_string) { YAML.dump(s3_data) }
    let(:mock_s3_response) {
      mock_response = double("mock_s3_response")
      allow(mock_response).to receive(:body).and_return(StringIO.new(s3_data_string))
      mock_response
    }

    let(:mock_s3) {
      mock_s3 = double(AWS::S3::Client)
      allow(AWS::S3::Client).to receive(:new).and_return(mock_s3)
      mock_s3
    }

    before :each do
      subject.instance_variable_set(:@s3_bucket, 'config_bucket')
      subject.instance_variable_set(:@s3_path, 'path1/path2')
    end

    it 'properly parses response' do
      allow(mock_s3).to receive(:get_object).and_return(mock_s3_response)
      expect(subject.send(:read_s3_file)).to eq(s3_data)
    end

    context 'with yaml comments' do
      let(:s3_data_string) { "---\n# example comment\nprimary: 50\nsecondary: 50" }

      it 'properly parses response' do
        allow(mock_s3).to receive(:get_object).and_return(mock_s3_response)
        expect(subject.send(:read_s3_file)).to eq(s3_data)
      end
    end

    it 'calls S3 API with proper bucket and key' do
      expect(mock_s3).to receive(:get_object).with(bucket: 'config_bucket', key: 'path1/path2').exactly(:once).and_return(mock_s3_response)
      subject.send(:read_s3_file)
    end

    context 'with s3 errors' do
      it 'returns an empty configuration' do
        expect(mock_s3).to receive(:get_object).and_raise(AWS::S3::Errors::NoSuchBucket)
        expect(subject.send(:read_s3_file)).to eq(nil)
      end
    end

    context 'with invalid yaml' do
      let(:s3_data_string) { "{" }

      it 'returns an empty configuration' do
        allow(mock_s3).to receive(:get_object).and_return(mock_s3_response)
        expect(subject.send(:read_s3_file)).to eq(nil)
      end
    end

    context 'with invalid schema' do
      let(:s3_data) { {"watchers" => [{"bogus" => 10}, {"morebogus" => 11}]} }

      it 'returns an empty configuration' do
        allow(mock_s3).to receive(:get_object).and_return(mock_s3_response)
        expect(subject.send(:read_s3_file)).to eq(nil)
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

    context 'with valid schema' do
      let(:schema) { {'primary' => 50, 'secondary' => 50} }

      it 'returns true' do
        expect(subject.send(:validate_s3_file_schema, schema)).to eq(true)
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
