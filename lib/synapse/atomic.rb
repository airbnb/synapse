require 'thread'

module Synapse
  class AtomicValue
    def initialize(initial_value)
      @mu = Mutex.new
      set(initial_value)
    end

    def get
      return @mu.synchronize { @value }
    end

    def set(new_value)
      @mu.synchronize {
        @value = new_value
      }
    end

    def get_and_set(new_value)
      return @mu.synchronize {
        original_value = @value
        @value = new_value
        original_value
      }
    end
  end
end
