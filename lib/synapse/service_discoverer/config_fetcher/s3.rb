require_relative './base'

require 'aws-sdk'
require 'yaml'
require 'json'

module Synapse
  class S3Fetcher < BaseFetcher
    def initialize(opts)
      super opts

      # Setup our AWS connection
      s3 = AWS::S3.new(YAML.load_file(@opts['credentials']))
      @config_bucket = s3.buckets[@opts['bucket']]

      raise ArgumentError, "#{@opts['bucket']} doesn't exist" \
        unless @config_bucket.exists?

    end

    def fetch(service)
      confFile = @config_bucket.objects[service]
      service_conf = nil
      if confFile.exists?

        # Try and parse the config
        begin
          conf = JSON.parse(confFile.read)
        rescue JSON::ParserError => e
          raise "config file #{service} is not json:\n#{e.inspect}"
        end

        raise "config does not have a synapse section" unless conf.key?('synapse')

        service_conf = conf['synapse']

        apply_default_fields(service_conf, service)
      else
        raise "Cannot find config for #{service}"
      end

      return service_conf
    end

    private
    def validate_fetcher_opts
      raise ArgumentError, "invalid method '#{@opts['method']}' for s3 fetcher" \
        unless @opts['method'] == 's3'
      raise ArgumentError, "missing or invalid bucket for s3 config fetcher" \
        unless @opts['bucket']
      raise ArgumentError, "missing or invalid credentials for s3 config fetcher" \
        unless @opts['credentials']
    end
  end
end
