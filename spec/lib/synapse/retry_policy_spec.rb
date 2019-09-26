require 'spec_helper'
require 'synapse/retry_policy'

describe "test with retry" do
  include Synapse::RetryPolicy

  it "default retry succeed" do
    expect_attempts = 1
    attempts = 0
    expected_result = "done"
    result = with_retry do
      attempts += 1
      expected_result
    end
    expect(result).to eq(expected_result)
    expect(attempts).to eq(expect_attempts)
  end

  it "default retry fail" do
    expect_attempts = 1
    attempts = 0
    expect {
      with_retry do
        attempts += 1
        raise StandardError
      end
    }.to raise_error(StandardError)
    expect(attempts).to eq(expect_attempts)
  end

  it "retry until succeed" do
    expect_attempts = 3
    attempts = 0
    expected_result = "done"
    result = with_retry(:max_attempts => expect_attempts) do
      attempts += 1
      if attempts < expect_attempts
        raise StandardError
      end
      expected_result
    end
    expect(result).to eq(expected_result)
    expect(attempts).to eq(expect_attempts)
  end

  it "retry until reaching max attempts" do
    expect_attempts = 3
    attempts = 0
    expect {
      with_retry(:max_attempts => expect_attempts) do
        attempts += 1
        raise StandardError
      end
    }.to raise_error(StandardError)
    expect(attempts).to eq(expect_attempts)
  end

  it "retry until success with retriable_errors" do
    expect_attempts = 3
    attempts = 0
    expected_result = "done"
    result = with_retry(:max_attempts => expect_attempts, :retriable_errors => IOError) do
      attempts += 1
      if attempts < expect_attempts
        raise IOError
      end
      expected_result
    end
    expect(result).to eq(expected_result)
    expect(attempts).to eq(expect_attempts)
  end

  it "retry until reaching max attempts with retriable_errors" do
    expect_attempts = 3
    attempts = 0
    expect {
      with_retry(:max_attempts => expect_attempts) do
        attempts += 1
        raise IOError
      end
    }.to raise_error(IOError)
    expect(attempts).to eq(expect_attempts)
  end

  it "immediately raise non-retriable error" do
    expect_attempts = 1
    attempts = 0
    expect {
      with_retry(:max_attempts => 3, :retriable_errors => IOError) do
        attempts += 1
        raise ArgumentError
      end
    }.to raise_error(ArgumentError)
    expect(attempts).to eq(expect_attempts)
  end

  it "immediately raise argument error with invaid max_attempts" do
    expect_attempts = 0
    attempts = 0
    expect {
      with_retry(:max_attempts => -1) do
        attempts += 1
      end
    }.to raise_error(ArgumentError)
    expect(attempts).to eq(expect_attempts)
  end

  it "immediately raise argument error with invaid max_attempts" do
    expect_attempts = 0
    attempts = 0
    expect {
      with_retry(:max_attempts => 1, :base_interval => 5, :max_interval => 3) do
        attempts += 1
      end
    }.to raise_error(ArgumentError)
    expect(attempts).to eq(expect_attempts)
  end

  it "immediately raise argument error with missing callback" do
    expect_attempts = 0
    attempts = 0
    expect {
      with_retry(:max_attempts => 1, :base_interval => 1, :max_interval => 5)
    }.to raise_error(ArgumentError)
    expect(attempts).to eq(expect_attempts)
  end


  it "test get retry interval" do
    base_interval = 1
    max_interval = 10
    expect(get_retry_interval(base_interval, max_interval, 1, 0)).to eq(base_interval)
    expect(get_retry_interval(base_interval, max_interval, 2, 0)).to eq(2)
    expect(get_retry_interval(base_interval, max_interval, 3, 0)).to eq(4)
    expect(get_retry_interval(base_interval, max_interval, 4, 0)).to eq(8)
    expect(get_retry_interval(base_interval, max_interval, 5, 0)).to eq(max_interval)
  end

  it "test get retry interval with elapsed" do
    base_interval = 1
    max_interval = 10
    expect(get_retry_interval(base_interval, max_interval, 1, 2)).to eq(base_interval)
    expect(get_retry_interval(base_interval, max_interval, 2, 2)).to eq(1)
    expect(get_retry_interval(base_interval, max_interval, 3, 2)).to eq(2)
    expect(get_retry_interval(base_interval, max_interval, 4, 5)).to eq(3)
    expect(get_retry_interval(base_interval, max_interval, 5, 5)).to eq(max_interval)
  end
end


