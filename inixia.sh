#!/usr/bin/env bash

set -Eeuo pipefail

INTERFACE_WLAN0=${INTERFACE_WLAN0:-wlp9s0}
INTERFACE_NAME=${INTERFACE_NAME:-viface}
INTERFACE_MAC_PREFIX=${INTERFACE_MAC_PREFIX:-00:1A:3F:11:22:}
IP_PREFIX=${IP_PREFIX:-10.0.0}
FIRST_STATION_IP=${FIRST_STATION_IP:-11}
MAX_STATIONS=0

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_root() {
    (( EUID == 0 )) || die "Run this script as root."
}

require_commands() {
    local command
    for command in "$@"; do
        command -v "$command" >/dev/null 2>&1 ||
            die "Required command not found: $command"
    done
}

parse_positive_integer() {
    [[ $1 =~ ^[0-9]{1,3}$ ]] || return 1
    REPLY=$((10#$1))
    (( REPLY > 0 ))
}

validate_config() {
    local octet
    local -a octets

    [[ $IP_PREFIX =~ ^[0-9]{1,3}(\.[0-9]{1,3}){2}$ ]] ||
        die "IP_PREFIX must contain three IPv4 octets."
    IFS=. read -r -a octets <<< "$IP_PREFIX"
    for octet in "${octets[@]}"; do
        (( 10#$octet <= 255 )) || die "Invalid IPv4 prefix: $IP_PREFIX"
    done
    [[ $INTERFACE_MAC_PREFIX =~ ^([[:xdigit:]]{2}:){5}$ ]] ||
        die "INTERFACE_MAC_PREFIX must contain five hexadecimal octets and a trailing colon."

    parse_positive_integer "$FIRST_STATION_IP" ||
        die "FIRST_STATION_IP must be between 1 and 254."
    FIRST_STATION_IP=$REPLY
    (( FIRST_STATION_IP <= 254 )) ||
        die "FIRST_STATION_IP must be between 1 and 254."
    MAX_STATIONS=$((255 - FIRST_STATION_IP))
}

read_station_count() {
    local value
    read -r -p "Number of stations: " value
    parse_positive_integer "$value" || die "Enter a positive integer."
    (( REPLY <= MAX_STATIONS )) ||
        die "The station count cannot exceed $MAX_STATIONS with the current IP range."
}

station_interface() {
    printf '%s%s' "$INTERFACE_NAME" "$1"
}

station_ip() {
    printf '%s.%s' "$IP_PREFIX" "$((FIRST_STATION_IP + $1 - 1))"
}

interface_exists() {
    ip link show dev "$1" >/dev/null 2>&1
}

add_station_interface() {
    local index=$1
    local interface
    local mac

    interface=$(station_interface "$index")
    printf 'Creating %s...\n' "$interface"
    iw dev "$INTERFACE_WLAN0" interface add "$interface" type station
    printf -v mac '%s%02X' "$INTERFACE_MAC_PREFIX" "$index"
    ip link set dev "$interface" address "$mac"
    ip link set dev "$interface" up
}

remove_station_interface() {
    local index=$1
    local interface

    interface=$(station_interface "$index")
    if interface_exists "$interface"; then
        ip link set dev "$interface" down
        iw dev "$interface" del
    fi
}

set_station_ip() {
    local index=$1
    local address

    address=$(station_ip "$index")
    ip address replace "$address/24" dev "$(station_interface "$index")"
}

connect_station() {
    local index=$1
    local interface
    local link_info

    interface=$(station_interface "$index")
    if ! interface_exists "$interface"; then
        add_station_interface "$index"
    fi

    link_info=$(iw dev "$interface" link 2>/dev/null || true)

    if ! grep -Fqx "SSID: $ssidName" <<< "$link_info"; then
        if grep -q '^Connected to' <<< "$link_info"; then
            iw dev "$interface" disconnect
        fi
        remove_station_interface "$index"
        add_station_interface "$index"
        set_station_ip "$index"
        printf 'Connecting %s to "%s"...\n' "$interface" "$ssidName"
        iw dev "$interface" connect "$ssidName"
        if (( index % 10 == 0 )); then
            sleep 1
        fi
    fi
}

connect_stations() {
    local index
    for ((index = 1; index <= station_count; index++)); do
        connect_station "$index"
    done
}

set_station_ips() {
    local index
    for ((index = 1; index <= station_count; index++)); do
        set_station_ip "$index"
    done
}

add_stations() {
    read_station_count
    station_count=$REPLY
    read -r -p "SSID to connect to: " ssidName
    [[ -n $ssidName ]] || die "SSID cannot be empty."
    iw dev "$INTERFACE_WLAN0" info >/dev/null 2>&1 ||
        die "Wireless interface not found: $INTERFACE_WLAN0"

    connect_stations
    set_station_ips
}

remove_stations() {
    local index
    local interface
    read_station_count
    station_count=$REPLY

    for ((index = 1; index <= station_count; index++)); do
        interface=$(station_interface "$index")
        if interface_exists "$interface"; then
            printf 'Removing %s...\n' "$interface"
            iw dev "$interface" disconnect >/dev/null 2>&1 || true
            ip link set dev "$interface" down
            iw dev "$interface" del
        else
            printf '%s does not exist; skipping.\n' "$interface"
        fi
    done
}

disconnect_stations() {
    local index
    local interface
    read_station_count
    station_count=$REPLY

    for ((index = 1; index <= station_count; index++)); do
        interface=$(station_interface "$index")
        if interface_exists "$interface"; then
            iw dev "$interface" disconnect
        else
            printf '%s does not exist; skipping.\n' "$interface"
        fi
    done
}

iperf_clients() {
    local index
    local start_ip
    local target_ip
    require_commands iperf
    read_station_count
    station_count=$REPLY
    read -r -p "First target IP suffix (1-254): " start_ip
    parse_positive_integer "$start_ip" || die "Enter an integer from 1 to 254."
    start_ip=$REPLY
    (( start_ip <= 254 )) || die "Target IP suffix cannot exceed 254."
    (( start_ip + station_count - 1 <= 254 )) ||
        die "The target IP range would exceed 254."

    for ((index = 0; index < station_count; index++)); do
        target_ip="$IP_PREFIX.$((start_ip + index))"
        printf 'Starting iperf client for %s...\n' "$target_ip"
        iperf -c "$target_ip" -t 40 -u -b 1M -i 5 &
    done
}

monitor_stations() {
    read_station_count
    station_count=$REPLY
    read -r -p "SSID to connect to: " ssidName
    [[ -n $ssidName ]] || die "SSID cannot be empty."
    iw dev "$INTERFACE_WLAN0" info >/dev/null 2>&1 ||
        die "Wireless interface not found: $INTERFACE_WLAN0"

    printf 'Monitoring %s stations; press Ctrl+C to stop.\n' "$station_count"
    connect_stations
    set_station_ips
    while true; do
        connect_stations
        sleep 5
    done
}

main() {
    local option
    require_root
    require_commands iw ip grep
    validate_config

    printf '%s\n' \
        "1 - Connect stations" \
        "2 - Remove stations" \
        "3 - iperf clients" \
        "4 - Monitor and reconnect stations" \
        "5 - Disconnect stations"
    read -r -p "Select an option: " option

    case $option in
        1) add_stations ;;
        2) remove_stations ;;
        3) iperf_clients ;;
        4) monitor_stations ;;
        5) disconnect_stations ;;
        *) die "Invalid option." ;;
    esac
}

main "$@"
