require 'synapse/service_watcher/base'
require 'aws-sdk'

module Synapse
  class EC2Watcher < BaseWatcher

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
      unless @haproxy['server_port_override']
        raise ArgumentError,
          "Missing server_port_override for service #{@name} - which port are backends listening on?"
      end

      unless @haproxy['server_port_override'].match(/^\d+$/)
        raise ArgumentError, "Invalid server_port_override value"
      end

      # Required, but can use well-known environment variables.
      %w[aws_access_key_id aws_secret_access_key aws_region].each do |attr|
        unless (@discovery[attr] || ENV[attr.upcase])
          raise ArgumentError, "Missing #{attr} option or #{attr.upcase} environment variable"
        end
      end
    end

    def watch
      last_backends = []
      until @should_exit
        begin
          start = Time.now
          current_backends = discover_instances

          if last_backends != current_backends
            log.info "synapse: ec2tag watcher backends have changed."
            last_backends = current_backends
            configure_backends(current_backends)
          else
            log.info "synapse: ec2tag watcher backends are unchanged."
          end

          sleep_until_next_check(start)
        rescue Exception => e
          log.warn "synapse: error in ec2tag watcher thread: #{e.inspect}"
          log.warn e.backtrace
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
            'port' => @haproxy['server_port_override'],
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

    def configure_backends(new_backends)
      if new_backends.empty?
        if @default_servers.empty?
          log.warn "synapse: no backends and no default servers for service #{@name};" \
            " using previous backends: #{@backends.inspect}"
        else
          log.warn "synapse: no backends for service #{@name};" \
            " using default servers: #{@default_servers.inspect}"
          @backends = @default_servers
        end
      else
        log.info "synapse: discovered #{new_backends.length} backends for service #{@name}"
        @backends = new_backends
      end
      @synapse.reconfigure!
    end
  end
end

