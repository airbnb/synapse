require 'spec_helper'

class Synapse::Synapse
  def initialize() end
  
  def set_service_watchers(watchers)
    @service_watchers = watchers
  end
  
  def get_service_watchers
    @service_watchers
  end
  
  class ServiceWatcher
    def self.create(service_name, service_config, synapse)
      return WatcherMock.new(service_name, false)
    end
  end
end

class WatcherMock
  def initialize(name, started)
    @name=name
    @started=started
  end
  def start 
    @started = true  
  end
  def stop
    @started = false
  end
  def started?
    @started
  end
  def name 
    @name
  end
end

describe Synapse::Synapse do
  subject { Synapse::Synapse.new() }
  
  context("when a watcher gets appended at runtime") do
    before(:each) {
      subject.set_service_watchers([])
    }
    it("creates the watcher, appends it to the list and starts it") {
      service_name = "serviceName"
      service_config = { "foo" => "bar" }
      subject.append_service_watcher(service_name, service_config)
      expect(subject.get_service_watchers.length).to be(1)
      expect(subject.get_service_watchers[0].started?).to be true 
    }
  end
  
  context("when a watcher gets removed at runtime") do
    before(:each) {
      watcher1 = WatcherMock.new("watcher1", true)
      watcher2 = WatcherMock.new("watcher2", true)
      subject.set_service_watchers([watcher1, watcher2])
    }
    it("stops the watcher and removes it from the list") {
      service_name = "watcher1"
      subject.remove_watcher_by_name(service_name)
      expect(subject.get_service_watchers.length).to be(1)
      expect(subject.get_service_watchers[0].name).to eq("watcher2") 
    }
  end
end