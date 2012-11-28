module Synapse


  def log(message)
    @@log = Logger.new STDOUT unless defined?(@@log)
    @@log.debug message
  end

  class Base

    def initialize
    end
  end
end
