#!/usr/bin/env bash

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

get_vpn_if_gw() {
    local vpn_if_hex_addr=''
    local vpn_if_dec_addr=''
    local vpn_if_addr=''
    local try_ip=''
    local vpn_if_gw=''

    vpn_if_hex_addr=$(grep "${VPN_IF_NAME}" /proc/net/route | awk '$2 == "00000000" { print $3 }')
    
    if [ -n "${vpn_if_hex_addr}" ]; then
        #shellcheck disable=SC2046
        vpn_if_dec_addr=$(printf "%d." $(echo "${vpn_if_hex_addr}" | sed 's/../0x& /g' | tr ' ' '\n' | tac) | sed 's/\.$/\n/')
    fi

    if [ -z "${vpn_if_dec_addr}" ]; then
        vpn_if_addr=$(ip addr show dev "${VPN_IF_NAME}" | grep -oP '([0-9]{1,3}[\.]){3}[0-9]{1,3}')
        for n in {1..254}; do
            try_ip="$(echo "${vpn_if_addr}" | cut -d'.' -f1-3).${n}"
            if [ "${try_ip}" != "${vpn_if_addr}" ]; then
                if nc -4 -vw1 "${try_ip}" 1 &>/dev/null 2>&1; then
                    vpn_if_gw=${try_ip}
                    break
                fi
            fi
        done
        if [ -n "${vpn_if_gw}" ]; then
            echo "${vpn_if_gw}"
        else
            return 1
        fi
    else 
        echo "${vpn_if_dec_addr}"
    fi
}

getpublicip() {
    # shellcheck disable=SC2086
    natpmpc -g ${VPN_GATEWAY} | grep -oP '(?<=Public.IP.address.:.).*'
}

findconfiguredport() {
    curl -s -k -i --header "Referer: ${QBITTORRENT_SERVER_HTTP_OR_HTTPS}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}" --cookie "$1" "${QBITTORRENT_SERVER_HTTP_OR_HTTPS}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/app/preferences" | grep -oP '(?<=\"listen_port\"\:)(\d{1,5})'
}

findactiveport() {
    # shellcheck disable=SC2086
    natpmpc -g ${VPN_GATEWAY} -a 0 0 udp ${NAT_LEASE_LIFETIME} >/dev/null 2>&1
    # shellcheck disable=SC2086
    natpmpc -g ${VPN_GATEWAY} -a 0 0 tcp ${NAT_LEASE_LIFETIME} | grep -oP '(?<=Mapped public port.).*(?=.protocol.*)'
}

qbt_login() {
    qbt_sid=$(curl -s -k -i --header "Referer: ${QBITTORRENT_SERVER_HTTP_OR_HTTPS}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}" --data "username=${QBITTORRENT_USER}" --data-urlencode "password=${QBITTORRENT_PASS}" "${QBITTORRENT_SERVER_HTTP_OR_HTTPS}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/auth/login" | grep -oP '(?!set-cookie:.)SID=.*(?=\;.HttpOnly\;)')
    return $?
}

qbt_changeport(){
    curl -s -k -i --header "Referer: ${QBITTORRENT_SERVER_HTTP_OR_HTTPS}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}" --cookie "$1" --data-urlencode "json={\"listen_port\":$2,\"random_port\":false,\"upnp\":false}" "${QBITTORRENT_SERVER_HTTP_OR_HTTPS}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/app/setPreferences" >/dev/null 2>&1
    return $?
}

qbt_checksid(){
    if curl -s -k --header "Referer: ${QBITTORRENT_SERVER_HTTP_OR_HTTPS}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}" --cookie "${qbt_sid}" "${QBITTORRENT_SERVER_HTTP_OR_HTTPS}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/app/version" | grep -qi forbidden; then
        return 1
    else
        return 0
    fi
}

qbt_isreachable(){
    # shellcheck disable=SC2086
    nc -4 -vw 5 ${QBITTORRENT_SERVER} ${QBITTORRENT_PORT} &>/dev/null 2>&1
}

fw_delrule(){
    if (docker exec "${VPN_CT_NAME}" /sbin/iptables -L INPUT -n | grep -qP "^ACCEPT.*${configured_port}.*"); then
        # shellcheck disable=SC2086
        docker exec "${VPN_CT_NAME}" /sbin/iptables -D INPUT -i "${VPN_IF_NAME}" -p tcp --dport ${configured_port} -j ACCEPT
        # shellcheck disable=SC2086
        docker exec "${VPN_CT_NAME}" /sbin/iptables -D INPUT -i "${VPN_IF_NAME}" -p udp --dport ${configured_port} -j ACCEPT
    fi
}

fw_addrule(){
    if ! (docker exec "${VPN_CT_NAME}" /sbin/iptables -L INPUT -n | grep -qP "^ACCEPT.*${active_port}.*"); then
        # shellcheck disable=SC2086
        docker exec "${VPN_CT_NAME}" /sbin/iptables -A INPUT -i "${VPN_IF_NAME}" -p tcp --dport ${active_port} -j ACCEPT
        # shellcheck disable=SC2086
        docker exec "${VPN_CT_NAME}" /sbin/iptables -A INPUT -i "${VPN_IF_NAME}" -p udp --dport ${active_port} -j ACCEPT
        return 0
    else
        return 1
    fi
}

get_portmap() {
    res=0
    public_ip=$(getpublicip)

    if ! qbt_checksid; then
        echo "$(timestamp) | qBittorrent Cookie invalid, getting new SessionID"
        if ! qbt_login; then
            echo "$(timestamp) | Failed getting new SessionID from qBittorrent"
	          return 1
        fi
    else
        echo "$(timestamp) | qBittorrent SessionID Ok!"
    fi

    configured_port=$(findconfiguredport "${qbt_sid}")
    active_port=$(findactiveport)

    echo "$(timestamp) | Public IP: ${public_ip}"
    echo "$(timestamp) | Configured Port: ${configured_port}"
    echo "$(timestamp) | Active Port: ${active_port}"

    # shellcheck disable=SC2086
    if [ ${configured_port} != ${active_port} ]; then
        if qbt_changeport "${qbt_sid}" ${active_port}; then
            if fw_delrule; then
                echo "$(timestamp) | IPTables rule deleted for port ${configured_port} on ${VPN_CT_NAME} container"
            fi
            echo "$(timestamp) | Port Changed to: $(findconfiguredport ${qbt_sid})"
        else
            echo "$(timestamp) | Port Change failed."
            res=1
        fi
    else
        echo "$(timestamp) | Port OK (Act: ${active_port} Cfg: ${configured_port})"
    fi

    if fw_addrule; then
        echo "$(timestamp) | IPTables rule added for port ${active_port} on ${VPN_CT_NAME} container"
    fi

    return $res
}

check_vpn_ct_health() {
    while true;
    do
        if ! docker inspect "${VPN_CT_NAME}" --format='{{json .State.Health.Status}}' | grep -q '"healthy"'; then
            echo "$(timestamp) | Waiting for ${VPN_CT_NAME} healthy state.."
            sleep 3
        else
            echo "$(timestamp) | VPN container ${VPN_CT_NAME} in healthy state!"
            break
        fi
    done
}

pre_reqs() {
    if [ -z "${VPN_GATEWAY}" ]; then
        VPN_GATEWAY=$(get_vpn_if_gw || echo '')
    fi
while read -r var; do
    [ -z "${!var}" ] && { echo "$(timestamp) | ${var} is empty or not set."; exit 1; }
done << EOF
QBITTORRENT_SERVER
QBITTORRENT_PORT
QBITTORRENT_SERVER_HTTP_OR_HTTPS
QBITTORRENT_USER
QBITTORRENT_PASS
VPN_GATEWAY
VPN_CT_NAME
VPN_IF_NAME
CHECK_INTERVAL
NAT_LEASE_LIFETIME
EOF

[ ! -S /var/run/docker.sock ] && { echo "$(timestamp) | Docker socket doesn't exist or is inaccessible"; exit 2; }

return 0
}

load_vals(){
    public_ip=$(getpublicip)
    if qbt_isreachable; then
        if qbt_login; then
            configured_port=$(findconfiguredport "${qbt_sid}")
        else
            echo "$(timestamp) | Unable to login to qBittorrent at ${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}"
            exit 7
        fi
    else
        echo "$(timestamp) | Unable to reach qBittorrent at ${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}"
        exit 6
    fi
    active_port=''
}

public_ip=
configured_port=
active_port=
qbt_sid=

# Wait for a healthy state on the VPN container
check_vpn_ct_health

if pre_reqs; then load_vals; fi

# shellcheck disable=SC2086
[ -z ${public_ip} ] && { echo "$(timestamp) | Unable to grab VPN Public IP. Please check configuration"; exit 3; }
# shellcheck disable=SC2086
[ -z ${configured_port} ] && { echo "$(timestamp) | qBittorrent configured port value is empty(?). Please check configuration"; exit 4; }
[ -z "${qbt_sid}" ] && { echo "$(timestamp) | Unable to grab qBittorrent SessionID. Please check configuration"; exit 5; }

while true;
do
    if get_portmap; then
        echo "$(timestamp) | NAT-PMP/UPnP Ok!"
    else
        echo "$(timestamp) | NAT-PMP/UPnP Failed"
    fi
    # shellcheck disable=SC2086
    echo "$(timestamp) | Sleeping for $(echo ${CHECK_INTERVAL}/60 | bc) minutes"
    # shellcheck disable=SC2086
    sleep ${CHECK_INTERVAL}
done

exit $?
