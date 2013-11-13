require_relative "./config_fetcher/base"
require_relative "./config_fetcher/s3"

module Synapse
  class ConfigFetcher

    @fetchers = {
      'base'=>BaseFetcher,
      's3'=>S3Fetcher,
    }

    # the method which actually dispatches watcher creation requests
    def self.create(opts)

      raise ArgumentError, "Missing fetcher method when trying to create config fetcher" \
        unless opts.has_key?('method')

      fetcher_method = opts['method']
      raise ArgumentError, "Invalid fetcher method #{fetcher_method}" \
        unless @fetchers.has_key?(fetcher_method)

      return @fetchers[fetcher_method].new(opts)
    end
  end
end
