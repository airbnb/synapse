require 'spec_helper'
require 'fileutils'
require 'synapse/config_generator/file_output'

describe Synapse::ConfigGenerator::FileOutput do
  subject { Synapse::ConfigGenerator::FileOutput.new(config['file_output']) }

  before(:example) do
    FileUtils.mkdir_p(config['file_output']['output_directory'])
  end

  after(:example) do
    FileUtils.rm_r(config['file_output']['output_directory'])
  end

  let(:mockwatcher_1) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('example_service')
    backends = [{ 'host' => 'somehost', 'port' => 5555}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return(
      {'file_output' => {}}
    )
    allow(mockWatcher).to receive(:revision).and_return(0)
    mockWatcher
  end
  let(:mockwatcher_2) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('foobar_service')
    backends = [{ 'host' => 'somehost', 'port' => 1234}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return(
      {'file_output' => {}}
    )
    allow(mockWatcher).to receive(:revision).and_return(0)
    mockWatcher
  end

  let(:mockwatcher_disabled) do
    mockWatcher = double(Synapse::ServiceWatcher)
    allow(mockWatcher).to receive(:name).and_return('disabled_service')
    backends = [{ 'host' => 'somehost', 'port' => 1234}]
    allow(mockWatcher).to receive(:backends).and_return(backends)
    allow(mockWatcher).to receive(:config_for_generator).and_return(
      {'file_output' => {'disabled' => true}}
    )
    allow(mockWatcher).to receive(:revision).and_return(0)
    mockWatcher
  end

  it 'updates the config' do
    expect(subject).to receive(:write_backends_to_file)
    subject.update_config([mockwatcher_1])
  end

  it 'ignores repeat configs' do
    expect(subject).to receive(:write_backends_to_file).once
    subject.update_config([mockwatcher_1])
    subject.update_config([mockwatcher_1])
  end

  it 'manages correct files' do
    subject.update_config([mockwatcher_1, mockwatcher_2, mockwatcher_disabled])
    FileUtils.cd(config['file_output']['output_directory']) do
      expect(Dir.glob('*.json').sort).to eql(['example_service.json', 'foobar_service.json'])
    end
    # Should clean up after itself
    FileUtils.cd(config['file_output']['output_directory']) do
      FileUtils.touch('disabled_service.json')
      subject.update_config([mockwatcher_1, mockwatcher_disabled])
      expect(Dir.glob('*.json')).to eql(['example_service.json'])
    end
    # Should clean up after itself
    subject.update_config([])
    FileUtils.cd(config['file_output']['output_directory']) do
      expect(Dir.glob('*.json')).to eql([])
    end
  end

  it 'writes correct content' do
    subject.update_config([mockwatcher_1])
    data_path = File.join(config['file_output']['output_directory'],
                          'example_service.json')
    old_backends = JSON.load(File.read(data_path))
    expect(old_backends.length).to eql(1)
    expect(old_backends.first['host']).to eql('somehost')
    expect(old_backends.first['port']).to eql(5555)
  end
end
