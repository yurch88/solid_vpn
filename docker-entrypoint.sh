#!/bin/sh

set -e

generate_keys() {
    priv=$(wg genkey)
    pub=$(echo "$priv" | wg pubkey)

    echo -e "Private Key:\t$priv"
    echo -e "Public Key:\t$pub"
}

start_server() {
    if [ -z "$SERVER_ADDRESS" ] || [ -z "$SERVERPORT" ]; then
        echo "$(date): Missing required environment variables SERVER_ADDRESS or SERVERPORT."
        exit 1
    fi

    server_address_prefix=$(echo $SERVER_ADDRESS | awk -F '.' '{print $1"."$2"."$3}')
    server_final_address="${server_address_prefix}.1/24"

    interfaces=$(find /etc/wireguard -type f -name "*.conf")
    if [ -z "$interfaces" ]; then
        echo "$(date): No configuration found. Generating default wg0.conf..."

        mkdir -p /etc/wireguard

        server_private_key=$(wg genkey)
        server_public_key=$(echo "$server_private_key" | wg pubkey)

        cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $server_private_key
Address = $server_final_address
ListenPort = $SERVERPORT
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

        echo "$(date): Server configuration created: /etc/wireguard/wg0.conf"
    fi

    start_interfaces() {
        for interface in $(find /etc/wireguard -type f -name "*.conf"); do
            echo "$(date): Starting WireGuard interface: $interface"
            wg-quick up "$interface"
        done
    }

    stop_interfaces() {
        for interface in $(find /etc/wireguard -type f -name "*.conf"); do
            echo "$(date): Stopping WireGuard interface: $interface"
            wg-quick down "$interface"
        done
    }

    start_interfaces

    if [ $IPTABLES_MASQ -eq 1 ]; then
        echo "Adding iptables NAT rule"
        iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
        ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    fi

    finish() {
        echo "$(date): Shutting down WireGuard"
        stop_interfaces
        if [ $IPTABLES_MASQ -eq 1 ]; then
            iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
            ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
        fi
        exit 0
    }

    trap finish TERM INT QUIT

    if [ $WATCH_CHANGES -eq 0 ]; then
        sleep infinity &
        wait $!
    else
        while inotifywait -e modify -e create /etc/wireguard; do
            stop_interfaces
            start_interfaces
        done
    fi
}

# Main entrypoint logic
if [ "$1" = "genkeys" ]; then
    generate_keys
else
    start_server
fi
