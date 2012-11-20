module Synapse
  class Base
    def initialize
      @@log = Logger.new STDOUT
      @@log.info 'starting synapse'
    end
  end
end
