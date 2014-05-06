require "yaml"

module Configuration

  def config
    @config ||= YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), 'minimum.conf.yaml'))
  end

end
