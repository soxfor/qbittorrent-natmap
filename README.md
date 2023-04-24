# qBittorrent-NatMap 

The objective of this container is to run a script that requests a port forward (via NAT-PMP) from the VPN provider and upon success changes the listening port of the qBittorrent client when running in Docker

This solution is currently in use and tested with [Gluetun](https://github.com/qdm12/gluetun) and [qBittorrent](https://github.com/linuxserver/docker-qbittorrent) from Linuxserver.io and with VPN fron ProtonVPN using Wireguard.

## What made me do this?

The need to improve the seeding/upload performance and not finding any work done for this scenario (qBittorrent using docker'ized VPN), but finding [this post on reddit](https://old.reddit.com/r/ProtonVPN/comments/10owypt/successful_port_forward_on_debian_wdietpi_using/) by u/TennesseeTater for Deluge made me try and do something similar. His post is also referenced in the [ProtonVPN Guide][1].

## Why not modify the Gluetun image and include natpmpc there?

Well, as far as I could find, Alpine Linux doesn't have natively the binary for **natpmpc**, the NAT-PMP client used to request the *port forward* as per the instructions for [manual mapping][1] on ProtonVPN. Gluetun is using alpine as it's base image.

On AlpineLinux package info: [natpmpc binary not found][2] and [here][3] a request still in open state.

If I had the binary needed on the Gluetun container a script running on the host system instead of the container would probably suffice, allowing the following action: doing "docker exec <container> natpmpc <args>"

## What does the script do/modify?

So far:

* Evaluates the required variables for execution (for now, if they're set) and if **docker.sock** was mapped from the host into the container
* If the above succeeds:
    * Get the VPN public IP
    * Grab the SessionID cookie from qBittorrent
    * Grab the current listen port from qBittorrent
* After the configured checks pass, a function to request and verify the port mapping starts
    * Using *natpmpc* a port mapping request is made to the address defined in `VPN_GATEWAY` for udp and tcp
    * Comparison is made between the current configured port in qBittorrent and the currently active mapped port from the VPN
    * If a condition of different port is found:
        * The new port is configured in qBittorrent, along with that it's also disabled the random port setting and UPnP mapping from the torrent client
        * A couple of commands are executed to add/remove iptables rules regarding the previous active and new active mapped port on the VPN container

These actions are performed continuously (in a loop, every 5 minutes (default, can be lowered/increased)), most likely an option to set a failure count will be added in the future.

## Configurable variables:

* QBITTORRENT_SERVER (Defaults to **localhost**)
    * If setting here an address not related to the `VPN_IF_NAME` (default: tun0) a few users have [reported](https://old.reddit.com/r/ProtonVPN/comments/11ubgvi/port_forward_with_qbittorrent_and_protonvpn_on/jcxirts/) needing to set `FIREWALL_OUTBOUND_SUBNETS` for the Gluetun/VPN container
    * For ProtonVPN using Wireguard and qBittorrent container using `VPN_CT_NAME` as network_mode this would be set to **10.2.0.2**
* QBITTORRENT_PORT (Defaults to **8080**)
* QBITTORRENT_USER (Defaults to **admin**)
* QBITTORRENT_PASS (Defaults to **adminadmin**)
* VPN_GATEWAY (Defaults to **empty**)
    * If not set the script will try and find it
    * The value for this variable will be the `VPN_IF_NAME` (default: tun0) gateway address, not the `VPN_ENDPOINT_IP` from the Gluetun/VPN Container when using Wireguard, [more info here](https://github.com/qdm12/gluetun/wiki/Custom-provider#wireguard-only).
    * For ProtonVPN using Wireguard this would be set to **10.2.0.1**
* VPN_CT_NAME (Defaults to **gluetun**)
* VPN_IF_NAME (Defaults to **tun0**)
* CHECK_INTERVAL (Defaults to **300s**)
* NAT_LEASE_LIFETIME (Defaults to **300s**)
    * Ideally both `CHECK_INTERVAL` and `NAT_LEASE_LIFETIME` should be set equal or the check interval lower than the lease lifetime, but never above.

[1]: https://protonvpn.com/support/port-forwarding-manual-setup/
[2]: https://pkgs.alpinelinux.org/contents?file=natpmpc&path=&name=&branch=edge
[3]: https://gitlab.alpinelinux.org/alpine/awall/-/issues/2220
