FROM debian:sid

RUN \
  apt-get update && \
  apt-get install -y ruby ruby-dev haproxy build-essential libghc-zlib-dev sudo && \
  rm -rf /var/lib/apt/lists/* && \
  sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/haproxy

COPY ./synapse-0.11.1.gem /opt/synapse/

RUN gem install /opt/synapse/synapse-0.11.1.gem

CMD ["synapse"]
