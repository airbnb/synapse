module Synapse
  def log
    @@log ||= Logger.new(STDOUT)
  end
end
