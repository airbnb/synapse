require 'synapse/service_watcher/base'
require 'aws-sdk'

module Synapse
  # AwsEcsWatcher will use the Amazon ECS and EC2 APIs to discover tasks and containers running in your Amazon ECS cluster.
  #
  # Recognized configuration keys are
  #   aws_region: For the region to speak to ECS and EC2 APIs
  #   aws_ecs_cluster: For the ECS cluster in which you want to discover tasks and containers
  #   aws_ecs_family: Is the family of TaskDefinition to discover, for example my_app, or redis
  #
  # Usage:
  #   You'll need to create a TaskDefinition for ECS specifying the service which needs discovery, as well as a linked container
  #   including both haproxy and synapse.  In the synapse container include standard synapse configuration with the ECS cluster and
  #   family set.  By default, this container will use the credentials from the EC2 instance to make calls to ECS and EC2.  With
  #   this configuration, your application container will now be able to use standard Docker mechanisms for speaking to a linked
  #   container but it will instead be routed to one of the running tasks for the specific TaskDefinition family.
  #
  class AwsEcsWatcher < BaseWatcher
    
    attr_reader :check_interval

    def start
      region = @discovery['aws_region'] || ENV['AWS_REGION']
      log.info "Connecting to ECS region: #{region}"
      if @discovery['aws_access_key_id'] && @discovery['aws_secret_access_key']
        @ec2 = Aws::EC2::Client.new(
          region: region,
	  access_key_id: @discovery['aws_access_key_id'],
	  secret_access_key: @discovery['aws_secret_access_key'] )
	@ecs = Aws::ECS::Client.new(
          region: region,
	  access_key_id: @discovery['aws_access_key_id'],
	  secret_access_key: @discovery['aws_secret_access_key'] )
      else
        @ec2 = Aws::EC2::Client.new(region: region)
	@ecs = Aws::ECS::Client.new(region: region)
      end
      
      @check_interval = @discovery['check_interval'] || 15.0

      log.info "synapse: aws_ecs watcher looking for tasks in cluster #{@discovery['aws_ecs_cluster']} " +
        "in family #{@discovery['aws_ecs_family']}"
      
      @watcher = Thread.new { watch }
    end

    def discover_tasks
      new_backends = []
      # api_task_ids returns an array of arrays of task_ids, so each iteration gives us 100 or less task_ids to work with
      api_task_ids.each do |task_ids|
        tasks = api_describe_tasks(task_ids)

	container_instance_arns = tasks.map(&:container_instance_arn)
	container_instances = api_describe_container_instances(container_instance_arns)

	# Need a lookup based on the arn later, so make the map here
	container_instance_map = container_instances.group_by(&:container_instance_arn)

	ec2_instance_ids = container_instances.map(&:ec2_instance_id).uniq
	ec2_instances = api_describe_instances(ec2_instance_ids)

	# Need a fast lookup on the ec2 instance id for IP and DNS later
	ec2_instance_map = {}
	ec2_instances.each do |reservation|
          reservation.instances.each do |instance|
            ec2_instance_map[instance.instance_id] = instance
	  end
	end

	# This loop iterates through each task, and for every container found in a single task
	# ensures that there is exactly 1 host port bound across all containers in the task to
	# remove ambiguity about which container and port to discover.
	tasks.each do |t|
          host_ports = []
	  # Make sure to only discover RUNNING tasks so pre-launch or post-shutdown aren't included
	  if t.last_status == "RUNNING"
            t.containers.each do |c|
              if c.network_bindings
                c.network_bindings.each do |nb|
                  if nb.host_port
                    host_ports << nb.host_port
		  end
		end
	      end
	    end
	  end
	  if host_ports.size == 1
            ci = container_instance_map[t.container_instance_arn].first
            instance = ec2_instance_map[ci.ec2_instance_id]
	    # Only discover private dns and ip, the format below is needed for synapse to configure haproxy
            new_backends << {
              'name' => instance.private_dns_name,
	      'host' => instance.private_ip_address,
	      'port' => host_ports.first
	    }
	  end
	end
      end
      new_backends
    end

    private
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" \
        unless @discovery['method'] == 'aws_ecs'
      raise ArgumentError, "aws_ecs_cluster is required for service #{@name}" \
        unless @discovery['aws_ecs_cluster']
      raise ArgumentError, "aws_ecs_family is required for service #{@name}" \
        unless @discovery['aws_ecs_family']
    end

    def watch
      last_backends = []
      until @should_exit
        begin
          start = Time.now
	  current_backends = discover_tasks

	  if last_backends != current_backends
            log.info "synapse: aws_ecs watcher backends have changed."
	    last_backends = current_backends
	    configure_backends(current_backends)
	  else
            log.info "synapse: aws_ecs watcher backends are unchanged."
	  end

	  sleep_until_next_check(start)
	rescue Exception => e
          log.warn "synapse: error in aws_ecs watcher thread: #{e.inspect}"
	  log.warn e.backtrace
	end
      end

      log.info "synapse: aws_ecs watcher exited successfully"
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

    def sleep_until_next_check(start_time)
      sleep_time = check_interval - (Time.now - start_time)
      if sleep_time > 0.0
        sleep(sleep_time)
      end
    end

    def api_task_ids
      @ecs.list_tasks(cluster: @discovery['aws_ecs_cluster'], family: @discovery['aws_ecs_family']).map(&:task_arns)
    end

    def api_describe_tasks(task_ids)
      @ecs.describe_tasks(cluster: @discovery['aws_ecs_cluster'], tasks: task_ids).tasks
    end

    def api_describe_container_instances(container_instance_arns)
      @ecs.describe_container_instances(cluster: @discovery['aws_ecs_cluster'], container_instances: container_instance_arns).container_instances
    end

    def api_describe_instances(ec2_instance_ids)
      @ec2.describe_instances(instance_ids: ec2_instance_ids).reservations
    end

  end
end

