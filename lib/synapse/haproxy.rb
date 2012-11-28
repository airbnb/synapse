module Synapse
  class Haproxy < Base
    attr_reader :opts
    def initialize(opts={})
      super()
      @opts = opts
    end

    def generate_main_config()
      main_config = <<EOC
# this config needs haproxy-1.1.28 or haproxy-1.2.1

global
	log 127.0.0.1	local0
	log 127.0.0.1	local1 notice
	#log loghost	local0 info
	maxconn 4096
	#chroot /usr/share/haproxy
	user haproxy
	group haproxy
	daemon
	#debug
	#quiet

defaults
	log	global
	mode	http
	option	httplog
	option	dontlognull
	retries	3
	option redispatch
	maxconn	2000
	contimeout	5000
	clitimeout	50000
	srvtimeout	50000

EOC
      return main_config
    end
    
    def generate_service_config(opts,backends)
      raise "you did not provide opts[:name]" if opts[:name].nil?
      raise "you did not provide opts[:listen]" if opts[:listen].nil?
      opts[:protocol] ||= 'http'
      opts[:balance] ||= 'roundrobin'

      backend_section = <<EOS
listen #{opts[:name]} #{opts[:listen]}
        mode #{opts[:protocol]}
        balance #{opts[:balance]}
EOS

      backends.each do |backend|
        raise "this backend does not have a name: #{backend.inspect}" unless backend[:name]
        raise "this backend does not have a host: #{backend.inspect}" unless backend[:host]
        raise "this backend does not have a port: #{backend.inspect}" unless backend[:port]

        backend_section << "        server #{backend[:name]} #{backend[:host]}:#{backend[:port]}\n"
      end
      backend_section << "\n"
      
      return backend_section
      
    end
  end
end
