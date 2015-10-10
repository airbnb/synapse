require 'fileutils'
require 'tempfile'

module Synapse
  class FileOutput
    include Logging
    attr_reader :opts, :name

    def initialize(opts)
      unless opts.has_key?("output_directory")
        raise ArgumentError, "flat file generation requires an output_directory key"
      end

      begin
        FileUtils.mkdir_p(opts['output_directory'])
      rescue SystemCallError => err
        raise ArgumentError, "provided output directory #{opts['output_directory']} is not present or creatable"
      end

      @opts = opts
      @name = 'file_output'
    end

    def tick(watchers)
    end

    def update_config(watchers)
      watchers.each do |watcher|
        write_backends_to_file(watcher.name, watcher.backends)
      end
    end

    def write_backends_to_file(service_name, new_backends)
      data_path = File.join(@opts['output_directory'], "#{service_name}.json")
      begin
        old_backends = JSON.load(File.read(data_path))
      rescue Errno::ENOENT
        old_backends = nil
      end

      if old_backends == new_backends
        # Prevent modifying the file unless something has actually changed
        # This way clients can set watches on this file and update their
        # internal state only when the smartstack state has actually changed
        return false
      else
        # Atomically write new sevice configuration file
        temp_path = File.join(@opts['output_directory'],
                              ".#{service_name}.json.tmp")
        File.open(temp_path, 'w', 0644) {|f| f.write(new_backends.to_json)}
        FileUtils.mv(temp_path, data_path)
        return true
      end
    end
  end
end
