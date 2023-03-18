# qbittorrent-natmap

Docker container to maintain and update the NAT-PMP/UPnP forwarded port to qBittorrent.

Tested with Gluetun using ProtonVPN (Wireguard) and qBittorrent.

This solution can probably need a few tweaks and error handling, also some work in opening only the needed port on the VPN container.

In the repo a sample docker-compose.yml can be found.

The following variables can be set:

- QBITTORRENT_SERVER    (Default: <not set>)*
- QBITTORRENT_PORT      (Default: 8080)
- QBITTORRENT_USER      (Default: admin)
- QBITTORRENT_PASS      (Default: adminadmin)
- VPN_CT_NAME           (Default: gluetun)
- VPN_IF_NAME           (Default: tun0)
- VPN_GATEWAY*          (Default: <not set>)*
- CHECK_INTERVAL        (Default: 300s)
- NAT_LEASE_TIME        (Default: 300s)
