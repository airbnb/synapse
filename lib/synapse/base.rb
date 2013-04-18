module Synapse
  def log
    @@log ||= Logger.new(STDOUT)
  end

  def safe_run(command)
    res = `#{command}`.chomp
    raise "command '#{command}' failed to run:\n#{res}" unless $?.success?
  end

  class Base
    def initialize
      super
    end
  end
end
