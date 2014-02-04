require 'spec_helper'

class Synapse::BaseWatcher
  attr_reader :should_exit, :default_servers
end

describe Synapse::BaseWatcher do
  let(:mocksynapse) { double() }
  subject { Synapse::BaseWatcher.new(args, mocksynapse) } 
  let(:testargs) { { 'name' => 'foo', 'discovery' => { 'method' => 'base' }, 'haproxy' => {} }}

  def remove_arg(name)
    args = testargs.clone
    args.delete name
    args
  end

  context "can construct normally" do
    let(:args) { testargs }
    it('can at least construct') { expect { subject }.not_to raise_error }
  end

  ['name', 'discovery', 'haproxy'].each do |to_remove|
    context "without #{to_remove} argument" do
      let(:args) { remove_arg to_remove }
      it('gots bang') { expect { subject }.to raise_error(ArgumentError, "missing required option #{to_remove}") }
    end
  end

  context "normal tests" do
    let(:args) { testargs }
    it('is running') { expect(subject.should_exit).to equal(false) }
    it('can ping') { expect(subject.ping?).to equal(true) }
    it('can be stopped') do
      subject.stop
      expect(subject.should_exit).to equal(true)
    end
  end

  context "with default_servers" do
    default_servers = ['server1', 'server2']
    let(:args) { testargs.merge({'default_servers' => default_servers}) }
    it('sets default backends to default_servers') { expect(subject.backends).to equal(default_servers) }
  end
end

