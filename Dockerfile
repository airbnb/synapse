FROM phusion/baseimage:0.9.10
ENV HOME /root
CMD ["/sbin/my_init"]
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

