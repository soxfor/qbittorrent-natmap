# qbittorrent-natmap

Docker container to maintain and update the NAT-PMP/UPnP forwarded port to qBittorrent.

Tested with Gluetun using ProtonVPN (Wireguard) and qBittorrent, it assumes that on the VPN container there's the following rules:

```console
# cat iptables/post-rules.txt
iptables -A INPUT -i tun0 -s 0.0.0.0/0 -d 0.0.0.0/0 -p tcp --dport 10000:65535 -j ACCEPT
iptables -A INPUT -i tun0 -s 0.0.0.0/0 -d 0.0.0.0/0 -p udp --dport 10000:65535 -j ACCEPT
```

This solution can probably need a few tweaks and error handling, also some work in opening only the needed port on the VPN container.
