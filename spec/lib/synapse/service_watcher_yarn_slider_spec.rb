require 'spec_helper'
require 'synapse/service_watcher/yarn_slider'

describe Synapse::ServiceWatcher::YarnSliderWatcher do
  let(:mocksynapse) { double() }
  let(:yarn_host) { '127.0.0.1' }
  let(:yarn_port) { '8088' }
  let(:app_name) { 'feeder' }
  let(:check_interval) { 11 }
  let(:yarn_request_uri) { "#{yarn_host}:#{yarn_port}/ws/v1/cluster/apps?limit=2&state=RUNNING&applicationTypes=org-apache-slider&applicationTags=name:%20feeder" }
  let(:slider_request_uri) { "#{yarn_host}:#{yarn_port}/proxy/application_1480417404363_0011/ws/v1/slider/publisher/slider/componentinstancedata" }
  let(:config) do
    {
      'name' => 'foo',
      'discovery' => {
        'method' => 'yarn',
        'yarn_api_url' => "http://#{yarn_host}:#{yarn_port}",
        'application_name' => app_name,
        'check_interval' => check_interval,
      },
      'haproxy' => {},
    }
  end
  let(:slider_response) { {'description' => 'ComponentInstanceData', 'updated' => 0, 'entries' =>  nil, 'empty' => false} }
  let(:yarn_response) { { 'apps' => nil } }

  subject { described_class.new(config, mocksynapse) }

  before do
    allow(subject.log).to receive(:warn)
    allow(subject.log).to receive(:info)
    allow(subject.log).to receive(:debug)

    allow(Thread).to receive(:new).and_yield
    allow(subject).to receive(:sleep)
    allow(subject).to receive(:only_run_once?).and_return(true)
    allow(subject).to receive(:splay).and_return(0)

    stub_request(:get, yarn_request_uri).
      with(:headers => {
        'Accept'=>'application/json', 
        'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 
        'Content-Type'=>'application/json', 
        'User-Agent'=>'Ruby'
      }).to_return(:body => JSON.generate(yarn_response))

    stub_request(:get, slider_request_uri).
      with(:headers => {
        'Accept'=>'application/json', 
        'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 
        'Content-Type'=>'application/json', 
        'User-Agent'=>'Ruby'
      }).to_return(:body => JSON.generate(slider_response))
  end

  context 'with a valid argument hash' do
    it 'instantiates' do
      expect(subject).to be_a(Synapse::ServiceWatcher::YarnSliderWatcher)
    end
  end

  describe '#watch' do
    context 'when synapse cannot connect to yarn' do
      before do
        allow(Net::HTTP).to receive(:new).
          with(yarn_host, yarn_port.to_i).
          and_raise(Errno::ECONNREFUSED)
      end

      it 'does not crash' do
        expect { subject.start }.not_to raise_error
      end
    end

    it 'requests the proper API endpoint one time' do
      subject.start
      expect(a_request(:get, yarn_request_uri)).to have_been_made.times(1)
    end

    context 'when yarn return empty apps' do
      it 'does not crash' do
        expect { subject.start }.not_to raise_error
      end
     it 'requests the proper API endpoint one time' do
      subject.start
      expect(a_request(:get, yarn_request_uri)).to have_been_made.times(1)
      end
    end

    context 'when slider return empty result' do
      let(:yarn_response) do
        {"apps"=> 
          {"app" => 
            [
              { "name" => "kafka_feeder",
                "trackingUrl" => "http://#{yarn_host}:#{yarn_port}/proxy/application_1480417404363_0011",
                "applicationTags" => "name: feeder,description: bit kafka feeder,version: 0.0.1"
              }
            ]
          }
        }
      end
      it 'does not crash' do
        expect { subject.start }.not_to raise_error
      end
      it 'requests the proper API endpoint one time' do
        subject.start
        expect(a_request(:get, yarn_request_uri)).to have_been_made.times(1)
        expect(a_request(:get, slider_request_uri)).to have_been_made.times(1)
      end
    end

    context 'when the API path (yarn_api_path) is customized' do
      let(:config) do
        super().tap do |c|
          c['discovery']['yarn_apps_path'] = '/v3/tasks/'
        end
      end

      let(:yarn_request_uri) { "#{yarn_host}:#{yarn_port}/v3/tasks/#{app_name}" }

      it 'calls the customized path' do
        subject.start
        expect(a_request(:get, yarn_request_uri)).to have_been_made.times(1)
      end
    end

    context 'with entries returned from slider' do
      let(:yarn_response) do
        {"apps"=> 
          {"app" => 
            [
              { "name" => "kafka_feeder",
                "trackingUrl" => "http://#{yarn_host}:#{yarn_port}/proxy/application_1480417404363_0011",
                "applicationTags" => "name: feeder,description: bit kafka feeder,version: 0.0.1"
              }
            ]
          }
        }
      end  
      let(:slider_response) do 
        {
          "description" => "ComponentInstanceData", 
          "updated" => 0, 
          "entries" => {
            "container_e02_1480417404363_0011_02_000002.server_port" => "dn0.dev:50009",
            "container_e02_1480417404363_0011_02_000003.server_port" => "dn0.dev:50006"
            }, 
          "empty" => false 
        }  
      end
      let(:expected_backend_hash1) do
        {
          'name' => 'container_e02_1480417404363_0011_02_000002', 'host' => 'dn0.dev', 'port' => "50009"
        }
      end  
      let(:expected_backend_hash2) do
        {
          'name' => 'container_e02_1480417404363_0011_02_000003', 'host' => 'dn0.dev', 'port' => "50006"
        }
      end

      it 'adds the task as a backend' do
        expect(subject).to receive(:set_backends).with([expected_backend_hash1,expected_backend_hash2])
        subject.start
        expect(a_request(:get, yarn_request_uri)).to have_been_made.times(1)
        expect(a_request(:get, slider_request_uri)).to have_been_made.times(1)
      end

      context 'with a entries with out right sufix' do
        let(:yarn_response) do
        {"apps"=> 
          {"app" => 
            [
              { "name" => "kafka_feeder",
                "trackingUrl" => "http://#{yarn_host}:#{yarn_port}/proxy/application_1480417404363_0011",
                "applicationTags" => "name: feeder,description: bit kafka feeder,version: 0.0.1"
              }
            ]
          }
        }
      end  
        let(:slider_response) do 
          {
            "description" => "ComponentInstanceData", 
            "updated" => 0, 
            "entries" => {
              "container_e02_1480417404363_0011_02_000002.host_port" => "dn0.dev:50009",
              "container_e02_1480417404363_0011_02_000003.host_port" => "dn0.dev:50006"
              }, 
            "empty" => false 
          }  
        end
        it 'filters tasks that have no startedAt value' do
          expect(subject).to receive(:set_backends).with([])
          subject.start
        end
      end

      context 'when yarn returns invalid response' do
        let(:yarn_response) { [] }
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