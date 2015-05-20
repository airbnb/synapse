require 'spec_helper'

class RateLimiter
  attr_accessor :time, :tokens, :last_restart_time
end

describe Synapse::RateLimiter do
  let(:subject) { Synapse::RateLimiter.new('test') }
  let(:file_like_object) { spy('file_like_object') }

  before {
    allow(File).to receive(:open).with('test', 'w').and_yield(file_like_object)
    allow(File).to receive(:read).and_raise(Errno::ENOENT.new)
  }

  it "saves state" do
    subject.time = 666
    subject.last_restart_time = 17
    subject.tokens = 42

    subject.tick

    expect(file_like_object).to have_received(:write).with(
      '{"time":667,"last_restart_time":17,"tokens":42}')
  end

  it "initializes" do
    expect(subject.time).to eql(0)
    expect(subject.last_restart_time).to eql(0)
    expect(subject.tokens).to eql(0)
  end

  it "handles the nil path" do
    subject = Synapse::RateLimiter.new(nil)
    subject.proceed?
  end

  it "loads state when available" do
    allow(File).to receive(:read).and_return(
      '{"time":667,"last_restart_time":17,"tokens":42}')
    expect(subject.time).to eql(667)
    expect(subject.last_restart_time).to eql(17)
    expect(subject.tokens).to eql(42)
  end

  it "yields a single token after the token period" do
    59.times do
      subject.tick
    end
    expect(subject.time).to eql(59)
    expect(subject.tokens).to eql(0)

    subject.tick
    expect(subject.time).to eql(60)
    expect(subject.tokens).to eql(1)
  end

  it "respects the maximum token value" do
    666.times do
      subject.tick
    end
    expect(subject.time).to eql(666)
    expect(subject.tokens).to eql(2)
  end

  it "does not allow client to proceed if there is no token" do
    subject.time = 666
    subject.last_restart_time = 0
    subject.tokens = 0

    expect(subject.proceed?).to eql(false)
  end

  it "allows client to proceed when there is a token" do
    subject.time = 666
    subject.last_restart_time = 0
    subject.tokens = 1

    expect(subject.proceed?).to eql(true)

    expect(subject.time).to eql(666)
    expect(subject.last_restart_time).to eql(666)
    expect(subject.tokens).to eql(0)
  end

  it "does not allow client to proceed too soon after last time" do
    subject.time = 666
    subject.last_restart_time = 665
    subject.tokens = 1

    expect(subject.proceed?).to eql(false)

    expect(subject.time).to eql(666)
    expect(subject.last_restart_time).to eql(665)
    expect(subject.tokens).to eql(1)
  end

  it "allows client to proceed once enough time has passed" do
    subject.time = 666
    subject.last_restart_time = 664
    subject.tokens = 1

    expect(subject.proceed?).to eql(true)

    expect(subject.time).to eql(666)
    expect(subject.last_restart_time).to eql(666)
    expect(subject.tokens).to eql(0)
  end
end
