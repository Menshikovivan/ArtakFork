#!/bin/sh
# Disposable OpenWrt VM only: stock WireGuard vs AmneziaWG kernel interop.
set -eu
umask 077
[ "${ARTAK_DISPOSABLE_VM:-}" = 1 ] || exit 1
cleanup() {
    ifdown atw 2>/dev/null || :
    ip netns del wg-interop 2>/dev/null || :
    uci -q delete network.atw || :
    uci -q delete network.atwp || :
    uci commit network
    rm -f /tmp/wgi-a /tmp/wgi-b /tmp/wgi-apub /tmp/wgi-bpub
    /etc/init.d/firewall start 2>/dev/null || :
}
trap cleanup EXIT
# The isolated VM uses LAN as its temporary QEMU package uplink. netifd
# reloads can recreate rejecting fw4 chains even after the provisioner stops
# the firewall, so clear them only inside this explicitly disposable VM.
/etc/init.d/firewall stop
nft flush ruleset
ip addr replace 10.0.2.15/24 dev br-lan
ip route replace default via 10.0.2.2 dev br-lan
apk add kmod-wireguard wireguard-tools >/dev/null
modprobe wireguard
ip netns add wg-interop
awg genkey >/tmp/wgi-a
wg genkey >/tmp/wgi-b
awg pubkey </tmp/wgi-a >/tmp/wgi-apub
wg pubkey </tmp/wgi-b >/tmp/wgi-bpub

# Configure the AWG side through the actual netifd handler, with no J/S/H/I
# obfuscation parameters. Both peers use generated, disposable test keys.
uci set network.atw=interface
uci set network.atw.proto=amneziawg
uci set network.atw.nohostroute=1
uci set "network.atw.private_key=$(cat /tmp/wgi-a)"
uci add_list network.atw.addresses=10.89.0.1/32
uci set network.atw.listen_port=29301
uci set network.atwp=amneziawg_atw
uci set "network.atwp.public_key=$(cat /tmp/wgi-bpub)"
uci set network.atwp.endpoint_host=127.0.0.1
uci set network.atwp.endpoint_port=29302
uci set network.atwp.route_allowed_ips=0
uci add_list network.atwp.allowed_ips=10.89.0.2/32
uci commit network
/etc/init.d/network reload
ifup atw
n=0
until [ "$(ubus call network.interface.atw status | jsonfilter -e '@.up')" = true ] && ip -o link show atw | grep -q '<[^>]*UP[,>]'; do
    n=$((n+1)); [ "$n" -lt 30 ] || { echo 'AWG interface not ready' >&2; exit 1; }
    sleep 1
done

# Create stock kernel WireGuard in the host namespace so its UDP socket uses
# host loopback, then move the device to isolate the inner test addresses.
ip link add wgt type wireguard
wg set wgt listen-port 29302 private-key /tmp/wgi-b peer "$(cat /tmp/wgi-apub)" endpoint 127.0.0.1:29301 allowed-ips 10.89.0.1/32
ip link set wgt netns wg-interop
ip -n wg-interop link set lo up
ip -n wg-interop addr add 10.89.0.2/32 dev wgt
ip -n wg-interop link set wgt up
ip -n wg-interop route add 10.89.0.1/32 dev wgt
ip route add 10.89.0.2/32 dev atw
ip netns exec wg-interop ping -c 5 -w 12 10.89.0.1 >/dev/null
awg show atw latest-handshakes | awk 'NR==1 && $2>0 {ok=1} END {exit !ok}'
ip netns exec wg-interop wg show wgt latest-handshakes | awk 'NR==1 && $2>0 {ok=1} END {exit !ok}'
echo WIREGUARD_AWG_INTEROP_PASSED
