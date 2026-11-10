#!/usr/bin/env bash

set -Eeuo pipefail

INTERFACE_LOCAL=${INTERFACE_LOCAL:-eth0}
IP_PREFIX=${IP_PREFIX:-10.0.0}
IPERF_PID_FILE=/run/inixia-endpoint-iperf-server.pid

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
}

read_ip_range() {
    local value
    read -r -p "Number of IP addresses: " value
    parse_positive_integer "$value" || die "Enter a positive integer."
    address_count=$REPLY
    (( address_count <= 254 )) ||
        die "The address count cannot exceed 254."

    read -r -p "First IP suffix (1-254): " value
    parse_positive_integer "$value" || die "Enter an integer from 1 to 254."
    first_ip=$REPLY
    (( first_ip <= 254 )) || die "IP suffix cannot exceed 254."
    (( first_ip + address_count - 1 <= 254 )) ||
        die "The IP range would exceed 254."
}

address_for_suffix() {
    printf '%s.%s' "$IP_PREFIX" "$1"
}

interface_exists() {
    ip link show dev "$INTERFACE_LOCAL" >/dev/null 2>&1
}

managed_server_pid() {
    local pid
    local command_line

    [[ -r $IPERF_PID_FILE ]] || return 1
    read -r pid < "$IPERF_PID_FILE"
    [[ $pid =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    command_line=$(ps -p "$pid" -o args= 2>/dev/null) || return 1
    [[ $command_line == *iperf* && $command_line == *"-s"* && $command_line == *"-u"* ]]
}

start_iperf_server() {
    local pid

    if managed_server_pid; then
        read -r pid < "$IPERF_PID_FILE"
        printf 'Managed UDP iperf server is already running (PID %s).\n' \
            "$pid"
        return
    fi
    if [[ -e $IPERF_PID_FILE ]]; then
        rm -f -- "$IPERF_PID_FILE"
    fi

    iperf -s -u &
    pid=$!
    printf '%s\n' "$pid" > "$IPERF_PID_FILE"
    sleep 1
    if ! managed_server_pid; then
        rm -f -- "$IPERF_PID_FILE"
        die "The UDP iperf server did not start. Check whether port 5001 is already in use."
    fi
    printf 'UDP iperf server started (PID %s).\n' "$pid"
}

stop_iperf_server() {
    local pid

    if ! managed_server_pid; then
        if [[ -e $IPERF_PID_FILE ]]; then
            rm -f -- "$IPERF_PID_FILE"
        fi
        return
    fi

    read -r pid < "$IPERF_PID_FILE"
    kill "$pid"
    rm -f -- "$IPERF_PID_FILE"
    printf 'Stopped the UDP iperf server started by this script (PID %s).\n' "$pid"
}

add_addresses() {
    local index
    local address
    read_ip_range
    interface_exists || die "Network interface not found: $INTERFACE_LOCAL"

    for ((index = 0; index < address_count; index++)); do
        address=$(address_for_suffix "$((first_ip + index))")
        printf 'Adding %s/24 to %s...\n' "$address" "$INTERFACE_LOCAL"
        ip address replace "$address/24" dev "$INTERFACE_LOCAL"
    done

    start_iperf_server
}

remove_addresses() {
    local index
    local address
    read_ip_range
    if interface_exists; then
        for ((index = 0; index < address_count; index++)); do
            address=$(address_for_suffix "$((first_ip + index))")
            if ip address del "$address/24" dev "$INTERFACE_LOCAL" 2>/dev/null; then
                printf 'Removed %s/24 from %s.\n' "$address" "$INTERFACE_LOCAL"
            else
                printf '%s/24 is not configured on %s; skipping.\n' \
                    "$address" "$INTERFACE_LOCAL"
            fi
        done
    else
        printf 'Network interface not found: %s; skipping address removal.\n' \
            "$INTERFACE_LOCAL"
    fi

    stop_iperf_server
}

main() {
    local option
    require_root
    require_commands ip ps
    validate_config

    printf '%s\n' \
        "1 - Add IP addresses and start the UDP iperf server" \
        "2 - Remove IP addresses and stop this script's iperf server"
    read -r -p "Select an option: " option

    case $option in
        1)
            require_commands iperf
            add_addresses
            ;;
        2) remove_addresses ;;
        *) die "Invalid option." ;;
    esac
}

main "$@"
