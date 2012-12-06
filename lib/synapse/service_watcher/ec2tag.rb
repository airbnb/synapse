require_relative "./base"

module Synapse
  class EC2Watcher < BaseWatcher
    def start
      # connect to ec2
      # find all servers whose @discovery['tag_name'] matches @discovery['tag_value']
      # call @synapse.configure
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'ec2tag' 
      raise ArgumentError, "a `server_port_override` option is required for ec2tag watchers" \
        unless @server_port_override
      raise ArgumentError, "missing aws credentials for service #{@name}" \
        unless (@discovery['aws_key'] && @discovery['aws_secret'])
      raise ArgumentError, "aws tag name is required for service #{@name}" \
        unless @discovery['tag_name']
      raise ArgumentError, "aws tag value required for service #{@name}" \
        unless @discovery['tag_value']
    end
  end
end

