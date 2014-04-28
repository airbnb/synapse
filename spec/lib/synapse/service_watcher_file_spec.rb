require 'spec_helper'
require 'tmpdir'

module Synapse
  class FileWatcher < BaseWatcher
    attr_reader :listener
  end
end

describe Synapse::FileWatcher do
  subject(:watcher) { described_class.new(opts, synapse) }

  let(:synapse) { double }
  let(:tmpdir) { Dir.mktmpdir }
  let(:path) { File.join(tmpdir, 'server.list') }
  let(:opts) do
    {
      "name" => "service",
      "haproxy" => {},
      "discovery" => {
        "method" => "file",
        "path" => path
      },
    }
  end

  before do
    FileUtils.touch(path)
  end
  after do
    FileUtils.remove(Dir[File.join(tmpdir, "*")])
    FileUtils.remove_dir(tmpdir)
  end

  describe "#start" do
    it "returns Listener object" do
      expect(watcher).to receive(:reload_backends).twice
      watcher.start
      sleep 1 # wait for Listener (because it runs async)
      open(path, 'w') {|f| f.write('host port') }
      sleep 1 # wait for Listener (because it runs async)
    end
  end

  describe "#reload_backends" do
    before do
      open(path, 'w') do |f|
        f.write(<<-EOC)
host1 port1
host2 port2
        EOC
      end
    end
    it "loads servers to @backends" do
      expect(synapse).to receive(:reconfigure!)
      watcher.send(:reload_backends)
      expect(watcher.backends).to eq([
        {"host" => "host1", "port" => "port1"},
        {"host" => "host2", "port" => "port2"},
      ])
    end
  end

end

