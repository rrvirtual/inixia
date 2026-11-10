# Inixia ("Is Not Ixia") Wi-Fi station simulation

The name **Inixia** is a play on the Ixia test equipment brand: it means **"Is
Not Ixia."** These scripts provide a lightweight way to simulate multiple
Wi-Fi clients; they are not an Ixia product or replacement. :P

## Status and motivation

These scripts were created some time ago to simulate multiple Wi-Fi clients from
one host and generate traffic to a second host. They have not been used recently
and should be treated as legacy utilities: the README describes their current
behavior, but they have not been verified.

Only `inixia.sh` and `endpoint.sh` are covered here.

## What the scripts do

- `inixia.sh` creates multiple virtual Wi-Fi station interfaces, connects them
  to an SSID, and assigns one IPv4 address to each interface. It can also
  disconnect or remove the interfaces, monitor/reconnect them, and start UDP
  `iperf` clients.
- `endpoint.sh` assigns multiple IPv4 addresses to a network interface and
  starts a UDP `iperf` server. It can remove those addresses and stop the server
  it started.

The scripts run independently on separate hosts. `inixia.sh` configures the
Wi-Fi station host; `endpoint.sh` configures the endpoint host.

## Requirements

- Linux and Bash.
- Root privileges (`sudo`).
- `ip` from iproute2 on both hosts.
- On the station host: `iw` and `grep`.
- On the endpoint host: `iperf` (the legacy iperf 2 command-line interface) and
  `ps`.
- A Wi-Fi adapter and driver that support multiple concurrent virtual station
  interfaces.
- An SSID that the station host can connect to. The script does not configure
  an access point or provide Wi-Fi credentials.

`ifconfig` is not required. Network addresses and link states are managed with
`ip`.

## Default address plan

Both scripts default to the `10.0.0.0/24` network:

| Host/interface | Default address |
| --- | --- |
| Station host, `viface1` | `10.0.0.11/24` |
| Station host, `viface2` | `10.0.0.12/24` |
| Further station interfaces | Continue sequentially, up to `.254` |
| Endpoint host | Addresses chosen interactively |

The endpoint addresses must be in the same subnet and must not conflict with
other devices. The client can be pointed at a sequential range of endpoint
addresses when starting `iperf` tests.

## Usage

Make the scripts executable if needed:

```bash
chmod +x inixia.sh endpoint.sh
```

Run each script as root on its corresponding host:

```bash
sudo ./inixia.sh
sudo ./endpoint.sh
```

Each launch performs one menu action and then exits, except for station
monitoring, which runs until interrupted. To run another action, launch the
script again. Set up the station interfaces and endpoint addresses/server first;
then launch the station host's `iperf` clients.

### Station host: `inixia.sh`

1. Select **1 - Connect stations**.
2. Enter the number of virtual stations and the SSID.
3. The script creates interfaces named `viface1`, `viface2`, and so on; assigns
   each a MAC address and IP address; then connects each interface.
4. Select **3 - iperf clients** to start one UDP client per station. Enter the
   number of clients and the first endpoint IP suffix. For example, with prefix
   `10.0.0` and suffix `21`, clients target `10.0.0.21`, `10.0.0.22`, etc.
5. Select **4 - Monitor and reconnect stations** to keep checking connections.
   Press Ctrl+C to stop monitoring.

Other menu options disconnect the requested interfaces or remove them
completely. Disconnecting leaves the virtual interfaces in place; removing
deletes them.

### Endpoint host: `endpoint.sh`

1. Select **1 - Add IP addresses and start the UDP iperf server**.
2. Enter the number of addresses and the first last-octet value. For example,
   count `3` and start `21` configures `10.0.0.21/24` through
   `10.0.0.23/24` on the selected interface, then starts the UDP server.
3. Select **2 - Remove IP addresses and stop this script's iperf server** to
   remove the chosen range and stop the server started by this script.

The endpoint interface defaults to `eth0`; the server listens on the default
UDP iperf port.

## Configuration

Configuration can be overridden with environment variables when starting a
script:

| Variable | Script | Default | Purpose |
| --- | --- | --- | --- |
| `INTERFACE_WLAN0` | `inixia.sh` | `wlp9s0` | Physical Wi-Fi interface used to create station interfaces |
| `INTERFACE_NAME` | `inixia.sh` | `viface` | Prefix for virtual station interface names |
| `INTERFACE_MAC_PREFIX` | `inixia.sh` | `00:1A:3F:11:22:` | First five MAC octets; the station number supplies the last octet |
| `FIRST_STATION_IP` | `inixia.sh` | `11` | First station's final IPv4 octet |
| `INTERFACE_LOCAL` | `endpoint.sh` | `eth0` | Endpoint network interface |
| `IP_PREFIX` | Both | `10.0.0` | First three IPv4 octets used for assigned and target addresses |

For example:

```bash
sudo env INTERFACE_WLAN0=wlan0 IP_PREFIX=192.168.50 ./inixia.sh
sudo env INTERFACE_LOCAL=enp1s0 IP_PREFIX=192.168.50 ./endpoint.sh
```

Use the same `IP_PREFIX` on both hosts. Choose non-overlapping IP ranges that
are valid for the subnet and do not conflict with existing addresses.

## Limitations and cautions

- These scripts change system network configuration and require root. Use them
  only on test hosts and networks where you are authorized to make those
  changes.
- Driver and hardware limits may prevent the creation or simultaneous
  operation of the requested number of Wi-Fi interfaces.
- The scripts do not configure an access point, a bridge, routing, DHCP, Wi-Fi
  security, or firewall rules.
- Station connections use `iw`; the script does not accept a passphrase.
- `iperf` traffic is UDP at 1 Mbit/s per client for 40 seconds. The client
  command uses the legacy `iperf` interface, not `iperf3`.
- Do not assign the same IP addresses on both hosts. Keep the station range
  (starting at `.11` by default) separate from the endpoint range.
- The endpoint records the PID of the `iperf` server it starts in
  `/run/inixia-endpoint-iperf-server.pid`. Its stop option targets that recorded
  server rather than killing unrelated `iperf` processes.
