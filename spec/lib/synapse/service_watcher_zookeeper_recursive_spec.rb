require "spec_helper"

class Synapse::ZookeeperRecursiveWatcher
  attr_reader :should_exit, :default_servers

  def get_zk
    @zk
  end

  def get_synapse
    @synapse
  end

  def set_subwatcher(subwatcher)
    @subwatcher = subwatcher
  end
end

describe Synapse::ZookeeperRecursiveWatcher do
  let(:mocksynapse) { double }
  subject { Synapse::ZookeeperRecursiveWatcher.new(args, mocksynapse) }
  let(:testargs) {
    {"name" => "foo",
     "discovery" => {
         "method" => "zookeeper_recursive",
         "hosts" => ["localhost:2181"],
         "path" => "/foo/synapse"
     },
     "haproxy" => {
         "option_with_param" => "has #[service] param"
     }
    }
  }

  context "can construct normally" do
    let(:args) { testargs }
    it("can at least construct") { expect { subject }.not_to raise_error }
  end

  def remove_discovery_arg(name)
    args = testargs.clone
    discovery = testargs["discovery"].clone
    discovery.delete name
    args["discovery"] = discovery
    args
  end

  context "without path argument" do
    let(:args) { remove_discovery_arg "path" }
    it("gots bang") { expect { subject }.to raise_error(ArgumentError, "invalid zookeeper path for service #{args["name"]}") }
  end

  {"path" => "invalid zookeeper path for service foo",
   "hosts" => "missing or invalid zookeeper host for service foo",
   "method" => "invalid discovery method "}.each do |to_remove, message|
    context "without path argument" do
      let(:args) { remove_discovery_arg to_remove }
      it("gots bang") { expect { subject }.to raise_error(ArgumentError, message) }
    end
  end

  context "when watcher gets started" do
    let(:args) { testargs }
    before(:each) do
      ZK = ZKMock
    end
    it("sets up the zk-client and registers for the path") {
      expect(subject.get_synapse).to receive(:append_service_watcher).
                                           with("_foo_synapse",
                                                {"discovery" => {"method" => "zookeeper", "path" => "/foo/synapse", "hosts" => ["localhost:2181"], "empty_backend_pool" => nil},
                                                 "haproxy" => {"option_with_param" => "has _foo_synapse param", "server_options" => "", "server_port_override" => nil, "backend" => [], "frontend" => [], "listen" => []}})
      subject.start
      expect(subject.get_zk.start_successful).to be true
    }
    context("when a registered event is fired") do
      before(:each) do
        ZK = ZKMock
        expect(subject.get_synapse).to receive(:append_service_watcher)
        subject.start
      end
      it("adds a new zookeeper service_watcher on child-events and discovers new services in the new directory") {
        expect(subject.get_synapse).to receive(:append_service_watcher).
                                             with("_foo_synapse_service1",
                                                  {"discovery" => {"method" => "zookeeper", "path" => "/foo/synapse/service1", "hosts" => ["localhost:2181"], "empty_backend_pool" => nil},
                                                   "haproxy" => {"option_with_param" => "has _foo_synapse_service1 param", "server_options" => "", "server_port_override" => nil, "backend" => [], "frontend" => [], "listen" => []}})
        subject.get_zk.set_children("/foo/synapse", ["service1"])
        expect(subject.get_synapse).to receive(:remove_watcher_by_name).with("_foo_synapse")
        subject.get_zk.fire_event("/foo/synapse", false)

        expect(subject.get_synapse).to receive(:append_service_watcher).
                                             with("_foo_synapse_service1_subservice",
                                                  {"discovery" => {"method" => "zookeeper", "path" => "/foo/synapse/service1/subservice", "hosts" => ["localhost:2181"], "empty_backend_pool" => nil},
                                                   "haproxy" => {"option_with_param" => "has _foo_synapse_service1_subservice param", "server_options" => "", "server_port_override" => nil, "backend" => [], "frontend" => [], "listen" => []}})
        expect(subject.get_synapse).to receive(:remove_watcher_by_name).with("_foo_synapse_service1")
        subject.get_zk.set_children("/foo/synapse/service1", ["subservice"])
        subject.get_zk.fire_event("/foo/synapse/service1", false)
      }
      it("removes a service_watcher on delete-events") {
        expect(subject.get_synapse).to receive(:remove_watcher_by_name).with("_foo_synapse")
        subject.get_zk.fire_event("/foo/synapse", true)
      }
    end
  end

  context("when watcher gets stopped") do
    let(:args) { testargs }
    before(:each) do
      subject.set_subwatcher(["service1"])
    end
    it("cleans up every subwatcher") {
      expect(subject.get_synapse).to receive(:remove_watcher_by_name).with("service1")
      subject.stop
    }
  end

  class ZKMock
    ZKMock::ZKStat = Struct.new(:ephemeralOwner, :name)
    class ZKMock::ZKEvent
      def initialize(is_delete_event)
        @is_delete_event = is_delete_event
      end
      def node_deleted?
        return @is_delete_event
      end
    end

    def initialize(zk_connect_string)
      @initialized = true
      @root = Tree.new(to_zk_node("root"), [])
      @registered_paths = {}
    end

    def exists?(path)
      @root.find(to_zk_path(path)).nil?
    end

    def create(path, *args)
      @root.add_path(to_zk_path(path))
    end

    def register(path, opts={}, &block)
      blocks = @registered_paths[path] || []
      blocks.push(block)
      @registered_paths[path] = blocks
    end

    def children(path, opts={})
      node = @root.find(to_zk_path(path))
      if node.nil? then
        return Array.new
      else
        return node.get_children.map { |child| extract_name(child.get_value) }
      end
    end

    def get(path)
      node = @root.find(to_zk_path(path))
      unless node.nil?
        node.get_value
      else
        raise Exception "Node does not exist!"
      end
    end

    # Helper
    def set_children(path, children)
      @root.add_path(to_zk_path(path))
      node = @root.find(to_zk_path(path))
      children.each { |child| node.add_child(Tree.new(to_zk_node(child), [])) }
    end

    def fire_event(path, is_delete_event)
      blocks = @registered_paths.delete(path)
      blocks.each { |block| block.call(ZKEvent.new(is_delete_event)) }
    end

    def start_successful
      return @initialized && @registered_paths.size > 0
    end

    def to_zk_path(path)
      path.split("/").drop(1).map { |node| to_zk_node(node) }
    end

    def to_zk_node(name)
      data = ""
      node_stat = ZKStat.new(0, name)
      return [data, node_stat]
    end

    def extract_name(zk_node)
      return zk_node[1]["name"]
    end
  end

end
