FROM ubuntu:jammy

LABEL version="0.1"
LABEL description="Map NAT-PMP/UPnP port and update qBittorrent configuration"

ARG DEBIAN_FRONTEND=noninteractive

RUN apt update
RUN apt install --no-install-suggests --no-install-recommends -y natpmpc curl bc
RUN rm -rf /var/lib/apt/lists/* /var/cache/apt/*
RUN apt clean

ENV QBITTORRENT_SERVER=''
ENV QBITTORRENT_PORT='8080'
ENV QBITTORRENT_USER='admin'
ENV QBITTORRENT_PASS='adminadmin'
ENV VPN_GATEWAY=''
ENV CHECK_INTERVAL='300'
ENV NAT_LEASE_LIFETIME='300'

COPY data/start.sh /start.sh
RUN chmod 750 /start.sh

CMD ["./start.sh"]
