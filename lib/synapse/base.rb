module Synapse
  def log(message)
    @@log = Logger.new STDOUT unless defined?(@@log)
    @@log.debug message
  end

  def safe_run(command)
    res = `command`.chomp
    raise "command '#{command}' failed to run:\n#{res}" unless $?.success?
  end

  class Base
    def initialize
      super
    end
  end
end
