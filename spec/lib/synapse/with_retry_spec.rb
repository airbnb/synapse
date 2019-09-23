require 'spec_helper'
require 'synapse/with_retry'

describe "test with retry" do
  it "no retry succeed" do
    expected_attemptes = 1
    attempts = 0
    expected_result = "done"
    result = Synapse.with_retry do
      attempts += 1
      expected_result
    end
    expect(result).to eq(expected_result)
    expect(attempts).to eq(expected_attemptes)
  end

  it "no retry fail" do
    expected_attemptes = 1
    attempts = 0
    expect {
      Synapse.with_retry do
        attempts += 1
        raise StandardError
      end
    }.to raise_error(StandardError)
    expect(attempts).to eq(expected_attemptes)
  end

  it "until succeed" do
    expected_attemptes = 3
    attempts = 0
    expected_result = "done"
    result = Synapse.with_retry(:max_attempts => expected_attemptes) do
      attempts += 1
      if attempts < expected_attemptes
        raise StandardError
      end
      expected_result
    end
    expect(result).to eq(expected_result)
    expect(attempts).to eq(expected_attemptes)
  end

  it "until reach max attempts" do
    expected_attemptes = 3
    attempts = 0
    expect {
      Synapse.with_retry(:max_attempts => expected_attemptes) do
        attempts += 1
        raise StandardError
      end
    }.to raise_error(StandardError)
    expect(attempts).to eq(expected_attemptes)
  end

  it "until succeed with retriable_errors" do
    expected_attemptes = 3
    attempts = 0
    expected_result = "done"
    result = Synapse.with_retry(:max_attempts => expected_attemptes, :retriable_errors => IOError) do
      attempts += 1
      if attempts < expected_attemptes
        raise IOError
      end
      expected_result
    end
    expect(result).to eq(expected_result)
    expect(attempts).to eq(expected_attemptes)
  end

  it "until reach max attempts with retriable_errors" do
    expected_attemptes = 3
    attempts = 0
    expect {
      Synapse.with_retry(:max_attempts => expected_attemptes) do
        attempts += 1
        raise IOError
      end
    }.to raise_error(IOError)
    expect(attempts).to eq(expected_attemptes)
  end

  it "immediate raise non-retriable error" do
    expected_attemptes = 1
    attempts = 0
    expect {
      Synapse.with_retry(:max_attempts => 3, :retriable_errors => IOError) do
        attempts += 1
        raise ArgumentError
      end
    }.to raise_error(ArgumentError)
    expect(attempts).to eq(expected_attemptes)
  end

  it "test get retry interval" do
    base_interval = 1
    max_interval = 10
    expect(Synapse.get_retry_interval(base_interval, max_interval, 1)).to eq(base_interval)
    expect(Synapse.get_retry_interval(base_interval, max_interval, 2)).to eq(2)
    expect(Synapse.get_retry_interval(base_interval, max_interval, 3)).to eq(4)
    expect(Synapse.get_retry_interval(base_interval, max_interval, 4)).to eq(8)
    expect(Synapse.get_retry_interval(base_interval, max_interval, 5)).to eq(max_interval)
  end


end


