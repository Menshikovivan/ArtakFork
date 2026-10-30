#!/bin/sh
# OpenWrt QEMU guest only. Creates disposable local test interfaces and keys.
set -eu
umask 077
[ -n "${ARTAK_MIRROR:-}" ] || { echo 'Missing isolated host package mirror' >&2; exit 1; }
n=0
while ! ip link show br-lan >/dev/null 2>&1 ||
      [ "$(ubus call network.interface.lan status 2>/dev/null | jsonfilter -e '@.up')" != true ]; do
    n=$((n+1)); [ "$n" -lt 90 ] || { echo 'br-lan startup timed out' >&2; exit 1; }
    sleep 1
done
ip addr flush dev br-lan
udhcpc -n -q -i br-lan >/dev/null
# Standalone udhcpc is not the netifd DHCP client; a lease message does not
# guarantee that its helper installed an address, route, or resolver.
ip addr replace 10.0.2.15/24 dev br-lan
ip route replace default via 10.0.2.2 dev br-lan
printf 'nameserver 10.0.2.3\n' > /tmp/resolv.conf
# The disposable VM uses its LAN as the temporary QEMU user-network uplink.
# Stock zone policy may reject that egress; the fw4 test later reloads it.
/etc/init.d/firewall stop
ip -4 route get 1.1.1.1
ping -q -c 1 -W 2 10.0.2.2 >/dev/null
sed -i "s#https://downloads.openwrt.org#$ARTAK_MIRROR/openwrt#g" /etc/apk/repositories.d/distfeeds.list
apk update >/dev/null
apk add ip-full >/dev/null
base=$ARTAK_MIRROR/2grey
suffix=v25.12.6_x86_64_x86_64.apk
wget -q -O /tmp/awg-tools.apk "$base/amneziawg-tools_$suffix"
wget -q -O /tmp/awg-kmod.apk "$base/kmod-amneziawg_$suffix"
echo 'faf1c0724742e557f1fb2c66e47369af774e2c3cd7bbec29c4af0db1c5781606  /tmp/awg-tools.apk' | sha256sum -c >/dev/null
echo '1eee085b856e1383893911b9e8e85f43c0cf536d8059fbdac024521395dd050f  /tmp/awg-kmod.apk' | sha256sum -c >/dev/null
# Never force installation past a kernel ABI/dependency failure.
apk --allow-untrusted --simulate add /tmp/awg-tools.apk /tmp/awg-kmod.apk >/dev/null
apk --allow-untrusted add /tmp/awg-tools.apk /tmp/awg-kmod.apk >/dev/null
modprobe amneziawg
command -v awg >/dev/null
# netifd may have loaded its protocol handlers before the package was added.
echo 'VM stage: restarting netifd'
if ! /etc/init.d/network restart; then echo 'VM stage: network restart returned failure' >&2; exit 1; fi
echo 'VM stage: netifd restarted'

run_profile() {
    profile=$1
    echo "VM stage: configuring $profile"
    awg genkey >/tmp/key-a; awg pubkey </tmp/key-a >/tmp/pub-a
    awg genkey >/tmp/key-b; awg pubkey </tmp/key-b >/tmp/pub-b
    awg genkey >/tmp/key-header
    for i in a b; do
        uci -q delete "network.at$i" || true
        uci -q delete "network.atp$i" || true
        uci set "network.at$i=interface"
        uci set "network.at$i.proto=amneziawg"
        uci set "network.at$i.nohostroute=1"
        uci set "network.at$i.private_key=$(cat /tmp/key-$i)"
        uci set "network.at$i.awg_jc=4"
        uci set "network.at$i.awg_jmin=40"
        uci set "network.at$i.awg_jmax=70"
        for n in 1 2 3 4; do uci set "network.at$i.awg_s$n=16"; done
        if [ "$profile" = 2.0 ]; then
            uci set "network.at$i.awg_h1=101-110"; uci set "network.at$i.awg_h2=201-210"
            uci set "network.at$i.awg_h3=301-310"; uci set "network.at$i.awg_h4=401-410"
        else
            uci set "network.at$i.awg_header_protection_key=$(cat /tmp/key-header)"
            uci set "network.at$i.awg_random_trailers=1"
            uci set "network.at$i.awg_disable_cookies=1"
        fi
        uci set "network.atp$i=amneziawg_at$i"
        uci set "network.atp$i.endpoint_host=127.0.0.1"
        uci set "network.atp$i.route_allowed_ips=0"
        uci set "network.atp$i.persistent_keepalive=2"
    done
    uci add_list network.ata.addresses=10.88.0.1/32
    uci add_list network.atb.addresses=10.88.0.2/32
    uci set network.ata.listen_port=29001; uci set network.atb.listen_port=29002
    uci set "network.atpa.public_key=$(cat /tmp/pub-b)"; uci set "network.atpb.public_key=$(cat /tmp/pub-a)"
    uci set network.atpa.endpoint_port=29002; uci set network.atpb.endpoint_port=29001
    uci add_list network.atpa.allowed_ips=10.88.0.2/32; uci add_list network.atpb.allowed_ips=10.88.0.1/32
    uci commit network
    echo "VM stage: reloading netifd for $profile"
    /etc/init.d/network reload
    echo "VM stage: starting $profile peers"
    ifup ata || { echo "ifup ata failed for $profile" >&2; exit 1; }
    ifup atb || { echo "ifup atb failed for $profile" >&2; exit 1; }
    n=0
    while [ "$(ubus call network.interface.ata status | jsonfilter -e '@.up')" != true ] ||
          [ "$(ubus call network.interface.atb status | jsonfilter -e '@.up')" != true ]; do
        n=$((n+1)); [ "$n" -lt 30 ] || {
            echo "netifd $profile readiness failed" >&2
            ubus call network.interface.ata status || true
            ubus call network.interface.atb status || true
            logread | grep -E 'netifd|amneziawg' | tail -40 | sed -E 's/[A-Za-z0-9+\/]{42,43}=/[REDACTED]/g' || true
            exit 1
        }
        sleep 1
    done
    # The moved interface retains its UDP socket in its creation namespace.
    ip netns add awg-peer
    echo "VM stage: testing $profile kernel tunnel"
    ip link set atb netns awg-peer
    ip -n awg-peer link set lo up
    # Moving a netdevice between Linux namespaces removes its IP addresses.
    ip -n awg-peer addr add 10.88.0.2/32 dev atb
    ip -n awg-peer link set atb up
    ip -n awg-peer route add 10.88.0.1/32 dev atb
    ip route add 10.88.0.2/32 dev ata
    if ! ip netns exec awg-peer ping -c 5 -w 12 10.88.0.1; then
        echo "VM $profile tunnel ping failed; diagnostic status follows" >&2
        ip -n awg-peer addr show atb || true
        ip -n awg-peer route show || true
        ip route get 10.88.0.2 || true
        echo 'Host handshake timestamps:'
        awg show ata latest-handshakes | awk '{print $2}' || true
        echo 'Peer handshake timestamps:'
        ip netns exec awg-peer awg show atb latest-handshakes | awk '{print $2}' || true
        logread | grep -E 'netifd|amneziawg' | tail -30 | sed -E 's/[A-Za-z0-9+\/]{42,43}=/[REDACTED]/g' || true
        exit 1
    fi
    echo "VM stage: $profile ping passed, checking handshakes"
    ip netns exec awg-peer awg show atb latest-handshakes | awk 'NR==1 && $2>0 {ok=1} END {exit !ok}'
    awg show ata latest-handshakes | awk 'NR==1 && $2>0 {ok=1} END {exit !ok}'
    echo "OpenWrt kmod/netifd $profile handshake and ping passed"
    ip netns exec awg-peer ip link del atb
    ip netns del awg-peer
    ifdown ata || true
    ifdown atb || true
    ip route del 10.88.0.2/32 dev ata 2>/dev/null || true
}
run_profile 2.0
run_profile 3.1
echo AWG_VM_ALL_TESTS_PASSED
