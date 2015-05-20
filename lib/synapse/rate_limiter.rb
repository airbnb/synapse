require 'json'

module Synapse
  class RateLimiter
    include Logging

    def initialize(path)
      @path = path

      # Our virtual clock
      @time = 0

      # Average at most one restart per minute, with the ability to burst to
      # two restarts per minute
      @tokens = 0
      @max_tokens = 2
      @token_period = 60

      # Restart at most once every two seconds
      @last_restart_time = 0
      @min_restart_period = 2

      # Try reading state back from disk
      unless @path.nil?
        begin
          data = JSON.parse(File.read(@path))
          @time = data["time"]
          @last_restart_time = data["last_restart_time"]
          @tokens = data["tokens"]
        rescue => e
          log.warn "Got error reading rate limiter state: #{e}"
        end
      end
    end

    # Should be invoked once per second
    def tick
      @time += 1

      # Add a token every @period ticks
      if @time % @token_period == 0
        @tokens = [@tokens + 1, @max_tokens].min
      end

      # Save state out to disk
      data = {
        "time" => @time,
        "last_restart_time" => @last_restart_time,
        "tokens" => @tokens,
      }
      unless @path.nil?
        begin
          File.open(@path, "w") do |f|
            f.write(data.to_json)
          end
        rescue
        end
      end
    end

    def proceed?
      # Is there an available token?
      if @tokens > 0
        # Has it been sufficiently long since our last restart?
        if @time - @min_restart_period >= @last_restart_time
          @tokens -= 1
          @last_restart_time = @time
          return true
        end
      end
      return false
    end
  end
end
