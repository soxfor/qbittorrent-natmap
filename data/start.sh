#!/usr/bin/env bash

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

getpublicip() {
    natpmpc -g ${VPN_GATEWAY} | grep -oP '(?<=Public.IP.address.:.).*'
}

findconfiguredport() {
    curl -s -i --header "Referer: http://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}" --cookie "$1" http://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/app/preferences | grep -oP '(?<=\"listen_port\"\:)(\d{1,5})'
}

findactiveport() {
    natpmpc -g ${VPN_GATEWAY} -a 0 0 tcp ${NAT_LEASE_LIFETIME} | grep -oP '(?<=Mapped public port.).*(?=.protocol.*)'
}

qbt_login() {
    curl -s -i --header "Referer: http://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}" --data "username=${QBITTORRENT_USER}&password=${QBITTORRENT_PASS}" http://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/auth/login | grep -oP '(?!set-cookie:.)SID=.*(?=\;.HttpOnly\;.path=\/\;)'
}

qbt_changeport(){
    curl -s -i --header "Referer: http://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}" --cookie "$1" --data-urlencode "json={\"listen_port\":$2,\"random_port\":false,\"upnp\":false}" http://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/app/setPreferences 2>&1 >/dev/null
    return $?
}

public_ip=''
qbt_sid=''
configured_port=''
active_port=''

check() {
    public_ip=$(getpublicip)
    qbt_sid=$(qbt_login)
    configured_port=$(findconfiguredport ${qbt_sid})
    active_port=$(findactiveport)

    echo "$(timestamp) | Public IP: ${public_ip}"
    echo "$(timestamp) | Configured Port: ${configured_port}"
    echo "$(timestamp) | Active Port: ${active_port}"

    if [ ${configured_port} != ${active_port} ]; then
        if qbt_changeport ${qbt_sid} ${active_port}; then
            sleep 3
            echo "$(timestamp) | Port Changed to: $(findconfiguredport ${qbt_sid})"
        else
            echo "$(timestamp) | Port Change failed."
        fi
    else
        echo "$(timestamp) | Port OK (Act: ${active_port} Cfg: ${configured_port})"
    fi
}

while true;
do
    check
    sleep ${CHECK_INTERVAL}
done

exit $?
