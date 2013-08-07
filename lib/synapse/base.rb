module Synapse
  def log
    @@log ||= Logger.new(STDERR)
  end
end
