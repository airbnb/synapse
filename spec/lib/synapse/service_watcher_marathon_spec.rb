require 'spec_helper'
require 'synapse/service_watcher/marathon'

describe Synapse::ServiceWatcher::MarathonWatcher do
  let(:mocksynapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end
  let(:marathon_host) { '127.0.0.1' }
  let(:marathon_port) { '8080' }
  let(:app_name) { 'foo' }
  let(:check_interval) { 11 }
  let(:marathon_request_uri) { "#{marathon_host}:#{marathon_port}/v2/apps/#{app_name}/tasks" }
  let(:config) do
    {
      'name' => 'foo',
      'discovery' => {
        'method' => 'marathon',
        'marathon_api_url' => "http://#{marathon_host}:#{marathon_port}",
        'application_name' => app_name,
        'check_interval' => check_interval,
      },
      'haproxy' => {},
    }
  end
  let(:marathon_response) { { 'tasks' => [] } }

  subject { described_class.new(config, mocksynapse) }

  before do
    allow(subject.log).to receive(:warn)
    allow(subject.log).to receive(:info)

    allow(Thread).to receive(:new).and_yield
    allow(subject).to receive(:sleep)
    allow(subject).to receive(:only_run_once?).and_return(true)
    allow(subject).to receive(:splay).and_return(0)

    stub_request(:get, marathon_request_uri).
      with(:headers => { 'Accept' => 'application/json' }).
      to_return(:body => JSON.generate(marathon_response))
  end

  context 'with a valid argument hash' do
    it 'instantiates' do
      expect(subject).to be_a(Synapse::ServiceWatcher::MarathonWatcher)
    end
  end

  describe '#watch' do
    context 'when synapse cannot connect to marathon' do
      before do
        allow(Net::HTTP).to receive(:new).
          with(marathon_host, marathon_port.to_i).
          and_raise(Errno::ECONNREFUSED)
      end

      it 'does not crash' do
        expect { subject.start }.not_to raise_error
      end
    end

    it 'requests the proper API endpoint one time' do
      subject.start
      expect(a_request(:get, marathon_request_uri)).to have_been_made.times(1)
    end

    context 'when the API path (marathon_api_path) is customized' do
      let(:config) do
        super().tap do |c|
          c['discovery']['marathon_api_path'] = '/v3/tasks/%{app}'
        end
      end

      let(:marathon_request_uri) { "#{marathon_host}:#{marathon_port}/v3/tasks/#{app_name}" }

      it 'calls the customized path' do
        subject.start
        expect(a_request(:get, marathon_request_uri)).to have_been_made.times(1)
      end
    end

    context 'with tasks returned from marathon' do
      let(:marathon_response) do
        {
          'tasks' => [
            {
              'host' => 'agouti.local',
              'id' => 'my-app_1-1396592790353',
              'ports' => [
                31336,
                31337
              ],
              'stagedAt' => '2014-04-04T06:26:30.355Z',
              'startedAt' => '2014-04-04T06:26:30.860Z',
              'version' => '2014-04-04T06:26:23.051Z'
            },
          ]
        }
      end
      let(:expected_backend_hash) do
        {
          'name' => 'agouti.local', 'host' => 'agouti.local', 'port' => 31336
        }
      end

      it 'adds the task as a backend' do
        expect(subject).to receive(:set_backends).with([expected_backend_hash])
        subject.start
      end

      context 'with a custom port_index' do
        let(:config) do
          super().tap do |c|
            c['discovery']['port_index'] = 1
          end
        end

        let(:expected_backend_hash) do
          {
            'name' => 'agouti.local', 'host' => 'agouti.local', 'port' => 31337
          }
        end

        it 'adds the task as a backend' do
          expect(subject).to receive(:set_backends).with([expected_backend_hash])
          subject.start
        end

        context 'when that port_index does not exist' do
          let(:config) do
            super().tap { |c| c['discovery']['port_index'] = 999 }
          end

          it 'does not include the backend' do
            expect(subject).to receive(:set_backends).with([])
            subject.start
          end
        end
      end

      context 'with a task that has not started yet' do
        let(:marathon_response) do
          super().tap do |resp|
            resp['tasks'] << {
              'host' => 'agouti.local',
              'id' => 'my-app_2-1396592790353',
              'ports' => [
                31336,
                31337
              ],
              'stagedAt' => '2014-04-04T06:26:30.355Z',
              'startedAt' => nil,
              'version' => '2014-04-04T06:26:23.051Z'
            }
          end
        end

        it 'filters tasks that have no startedAt value' do
          expect(subject).to receive(:set_backends).with([expected_backend_hash])
          subject.start
        end
      end

      context 'when marathon returns invalid response' do
        let(:marathon_response) { [] }
        it 'does not blow up' do
          expect { subject.start }.to_not raise_error
        end
      end

      context 'when the job takes a long time for some reason' do
        let(:job_duration) { 10 } # seconds

        before do
          actual_time = Time.now
          time_offset = -1 * job_duration
          allow(Time).to receive(:now) do
            # on first run, return the right time
            # subsequently, add in our job_duration offset
            actual_time + (time_offset += job_duration)
          end
          allow(subject).to receive(:set_backends)
        end

        it 'only sleeps for the difference' do
          expect(subject).to receive(:sleep).with(check_interval - job_duration)
          subject.start
        end
      end
    end
  end
end

