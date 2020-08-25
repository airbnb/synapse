# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'synapse/version'

Gem::Specification.new do |gem|
  gem.name          = "synapse"
  gem.version       = Synapse::VERSION
  gem.authors       = ["Martin Rhoads", "Igor Serebryany", "Joseph Lynch"]
  gem.email         = ["martin.rhoads@airbnb.com", "igor.serebryany@airbnb.com", "jlynch@yelp.com"]
  gem.description   = "Synapse is a daemon used to dynamically configure and "\
                      "manage local instances of HAProxy as well as local files "\
                      "in reaction to changes in a service registry such as "\
                      "zookeeper. Synapse is half of SmartStack, and is designed "\
                      "to be operated along with Nerve or another system that "\
                      "registers services such as Aurora."
  gem.summary       = %q{Dynamic HAProxy configuration daemon}
  gem.homepage      = "https://github.com/airbnb/synapse"

  gem.files         = Dir["**/*"]
  gem.executables   = Dir["bin/**/*"].map{ |f| File.basename(f) }
  gem.test_files    = Dir["spec/**/*"]

  gem.add_runtime_dependency "aws-sdk", "~> 1.39"
  gem.add_runtime_dependency "docker-api", "~> 1.7"
  gem.add_runtime_dependency "zk", "~> 1.9.4"
  gem.add_runtime_dependency "logging", "~> 1.8"
  gem.add_runtime_dependency "hashdiff", "~> 0.2.3"
  gem.add_runtime_dependency "dogstatsd-ruby", "~> 3.3.0"
  gem.add_runtime_dependency "nokogiri", "~> 1.6.8.1"
  gem.add_runtime_dependency "concurrent-ruby", "~> 1.1.6"

  gem.add_development_dependency "rake", "~> 11"
  gem.add_development_dependency "rspec", "~> 3.1.0"
  gem.add_development_dependency "factory_girl", "~> 4.7"
  gem.add_development_dependency "pry"
  gem.add_development_dependency "pry-nav"
  gem.add_development_dependency "webmock", "~> 1.22"
  gem.add_development_dependency "timecop"
  gem.add_development_dependency "simplecov", "~> 0.17.1"
  gem.add_development_dependency "simplecov-json", "0.2.0"
end
