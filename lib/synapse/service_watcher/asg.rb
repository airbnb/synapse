require 'synapse/service_watcher/base'
require 'aws-sdk'

class Synapse::ServiceWatcher
  class AsgWatcher < BaseWatcher

    attr_reader :check_interval

    def start
      region = @discovery['aws_region'] || ENV['AWS_REGION']
      log.info "Connecting to EC2 region: #{region}"

      @asg_client = AWS::AutoScaling::Client.new(
          region:            region,
          access_key_id:     @discovery['aws_access_key_id']     || ENV['AWS_ACCESS_KEY_ID'],
          secret_access_key: @discovery['aws_secret_access_key'] || ENV['AWS_SECRET_ACCESS_KEY'] )

      @ec2_client = AWS::EC2::Client.new(
          region:            region,
          access_key_id:     @discovery['aws_access_key_id']     || ENV['AWS_ACCESS_KEY_ID'],
          secret_access_key: @discovery['aws_secret_access_key'] || ENV['AWS_SECRET_ACCESS_KEY'] )

      @check_interval = @discovery['check_interval'] || 15.0

      log.info "synapse: asg watcher looking for instances in asg #{@discovery["asg_name"]}"

      @watcher = Thread.new { watch }
    end

    private

    def validate_discovery_opts
      # Required, via options only.
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'asg'
      raise ArgumentError, "aws asg name is required for service #{@name}" \
        unless @discovery['asg_name']

      # As we're only looking up instances with hostnames/IPs, need to
      # be explicitly told which port the service we're balancing for listens on.
      unless @haproxy['server_port_override']
        raise ArgumentError,
              "Missing server_port_override for service #{@name} - which port are backends listening on?"
      end

      unless @haproxy['server_port_override'].to_s.match(/^\d+$/)
        raise ArgumentError, "Invalid server_port_override value"
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
            log.info "synapse: asg watcher backends have changed."
          end
        rescue Exception => e
          log.warn "synapse: error in asg watcher thread: #{e.inspect}"
          log.warn e.backtrace
        ensure
          sleep_until_next_check(start)
        end
      end

      log.info "synapse: asg watcher exited successfully"
    end

    def sleep_until_next_check(start_time)
      sleep_time = check_interval - (Time.now - start_time)
      if sleep_time > 0.0
        sleep(sleep_time)
      end
    end

    def discover_instances
      AWS.memoize do
        instances = instances_in_asg(@discovery['asg_name'])

        new_backends = []

        # choice of private_dns_name, dns_name, private_ip_address or
        # ip_address, for now, just stick with the private fields.
        instances.each do |instance|
          new_backends << {
              'name' => instance.private_dns_name,
              'host' => instance.private_ip_address,
              'port' => @haproxy['server_port_override'],
          }
        end

        new_backends
      end
    end

    def instances_in_asg(asg_name)
      instances(instance_ids_in_asg(asg_name))
    end

    def instance_ids_in_asg(asg_name)
      asgs = @asg_client.describe_auto_scaling_groups({
          auto_scaling_group_names: [asg_name]
      }).auto_scaling_groups

      if asgs.length == 0
        log.error "synapse: no ASGs returned for ASG name #{asg_name}"
        return []
      elsif asgs.length > 1
        raise "synapse: #{asgs.length} ASGs returned for ASG name #{asg_name}. This shouldn't be possible!"
      else
        asg = asgs[0]
      end

      instance_ids = asg.instances
        .select {|i| i.lifecycle_state == 'InService' }
        .map { |i| i.instance_id }
    end

    def instances(instance_ids)
      if instance_ids.empty?
        []
      else
        @ec2_client.describe_instances({ instance_ids: Array(instance_ids) }).reservation_set[0].instances_set
      end
    end

  end
end

