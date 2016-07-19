require 'synapse/service_watcher/base'
require 'aws-sdk'

class Synapse::ServiceWatcher
  class Ec2tagWatcher < BaseWatcher

    attr_reader :check_interval

    def start
      region = @discovery['aws_region'] || ENV['AWS_REGION']
      log.info "Connecting to EC2 region: #{region}"

      @ec2 = AWS::EC2.new(
        region:            region,
        access_key_id:     @discovery['aws_access_key_id']     || ENV['AWS_ACCESS_KEY_ID'],
        secret_access_key: @discovery['aws_secret_access_key'] || ENV['AWS_SECRET_ACCESS_KEY'] )

      @check_interval = @discovery['check_interval'] || 15.0

      log.info "synapse: ec2tag watcher looking for instances " +
        "tagged with #{@discovery['tag_name']}=#{@discovery['tag_value']}"

      @watcher = Thread.new { watch }
    end

    private

    def validate_discovery_opts
      # Required, via options only.
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'ec2tag'
      raise ArgumentError, "aws tag name is required for service #{@name}" \
        unless @discovery['tag_name']
      raise ArgumentError, "aws tag value required for service #{@name}" \
        unless @discovery['tag_value']

      # As we're only looking up instances with hostnames/IPs, need to
      # be explicitly told which port the service we're balancing for listens on.
      unless @backend_port_override
        raise ArgumentError,
          "Missing backend_port_override for service #{@name} - which port are backends listening on?"
      end

      unless @backend_port_override.to_s.match(/^\d+$/)
        raise ArgumentError, "Invalid backend_port_override value"
      end

      # aws region is optional in the SDK, aws will use a default value if not provided
      unless @discovery['aws_region'] || ENV['AWS_REGION']
        log.info "aws region is missing, will use default"
      end
      # access key id & secret are optional, might be using IAM instance profile for credentials
      unless ((@discovery['aws_access_key_id'] || ENV['aws_access_key_id']) \
              && (@discovery['aws_secret_access_key'] || ENV['aws_secret_access_key'] ))
        log.info "aws access key id & secret not set in config or env variables for service #{name}, will attempt to use IAM instance profile"
      end
    end

    def watch
      until @should_exit
        begin
          start = Time.now
          if set_backends(discover_instances)
            log.info "synapse: ec2tag watcher backends have changed."
          end
        rescue Exception => e
          log.warn "synapse: error in ec2tag watcher thread: #{e.inspect}"
          log.warn e.backtrace
        ensure
          sleep_until_next_check(start)
        end
      end

      log.info "synapse: ec2tag watcher exited successfully"
    end

    def sleep_until_next_check(start_time)
      sleep_time = check_interval - (Time.now - start_time)
      if sleep_time > 0.0
        sleep(sleep_time)
      end
    end

    def discover_instances
      AWS.memoize do
        instances = instances_with_tags(@discovery['tag_name'], @discovery['tag_value'])

        new_backends = []

        # choice of private_dns_name, dns_name, private_ip_address or
        # ip_address, for now, just stick with the private fields.
        instances.each do |instance|
          new_backends << {
            'name' => instance.private_dns_name,
            'host' => instance.private_ip_address,
          }
        end

        new_backends
      end
    end

    def instances_with_tags(tag_name, tag_value)
      @ec2.instances
        .tagged(tag_name)
        .tagged_values(tag_value)
        .select { |i| i.status == :running }
    end
  end
end

