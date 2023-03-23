# syntax=docker/dockerfile:1

FROM ubuntu:jammy AS docker-cli

RUN apt update && \
    apt install --no-install-suggests --no-install-recommends -y ca-certificates curl gnupg lsb-release
RUN mkdir -m 0755 -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN apt update && \
    apt install --no-install-suggests --no-install-recommends -y docker-ce-cli

FROM ubuntu:jammy

LABEL org.opencontainers.image.source="https://github.com/soxfor/qbittorrent-natmap"
LABEL org.opencontainers.image.base.name="ubuntu:jammy"
LABEL description="Map port via NAT-PMP and update qBittorrent configuration"
LABEL version="1.0.4"

ARG DEBIAN_FRONTEND=noninteractive

RUN apt update
RUN apt install --no-install-suggests --no-install-recommends -y natpmpc curl bc netcat-openbsd
RUN rm -rf /var/lib/apt/lists/* /var/cache/apt/*
RUN apt clean

ENV QBITTORRENT_SERVER=
ENV QBITTORRENT_PORT=8080
ENV QBITTORRENT_USER=admin
ENV QBITTORRENT_PASS=adminadmin
ENV VPN_GATEWAY=
ENV VPN_CT_NAME=gluetun
ENV VPN_IF_NAME=tun0
ENV CHECK_INTERVAL=300
ENV NAT_LEASE_LIFETIME=300

COPY --from=docker-cli /usr/bin/docker /usr/bin/docker
COPY data/start.sh /start.sh

RUN chmod 750 /start.sh

CMD ["./start.sh"]
