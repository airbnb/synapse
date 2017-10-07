require "yaml"
require "erb"

module Configuration
  def config
    filename = File.join(File.dirname(File.expand_path(__FILE__)), 'minimum.conf.yaml')
    @config ||= YAML::load(ERB.new(File.read(filename)).result)
  end
end
