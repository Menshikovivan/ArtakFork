#!/bin/sh
# Exercise Linux policy routing without touching the host network. This tests
# socket routing primitives only; it does not test netifd or an AWG handshake.
set -eu
ROUTER="afrt$$"
REMOTE="afpeer$$"
WORK=$(mktemp -d)
SERVER=''
cleanup() {
    if [ -n "$SERVER" ]; then kill "$SERVER" 2>/dev/null || true; fi
    ip netns del "$ROUTER" 2>/dev/null || true
    ip netns del "$REMOTE" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM
ip netns add "$ROUTER"
ip netns add "$REMOTE"
ip -n "$ROUTER" link add afwan type veth peer name afwanp netns "$REMOTE"
ip -n "$ROUTER" link add afawg type veth peer name afawgp netns "$REMOTE"
ip -n "$ROUTER" link set lo up
ip -n "$REMOTE" link set lo up
ip -n "$ROUTER" addr add 192.0.2.1/24 dev afwan
ip -n "$REMOTE" addr add 192.0.2.2/24 dev afwanp
ip -n "$ROUTER" addr add 198.51.100.1/24 dev afawg
ip -n "$REMOTE" addr add 198.51.100.2/24 dev afawgp
ip -n "$REMOTE" addr add 203.0.113.77/32 dev lo
ip -n "$ROUTER" -6 addr add fd00:1::1/64 dev afwan nodad
ip -n "$REMOTE" -6 addr add fd00:1::2/64 dev afwanp nodad
ip -n "$ROUTER" -6 addr add fd00:2::1/64 dev afawg nodad
ip -n "$REMOTE" -6 addr add fd00:2::2/64 dev afawgp nodad
for spec in "$ROUTER afwan" "$ROUTER afawg" "$REMOTE afwanp" "$REMOTE afawgp"; do
    set -- $spec
    ip -n "$1" link set "$2" up
done
ip -n "$ROUTER" route add default via 192.0.2.2 dev afwan
# A static neighbour makes a device-only route work on Ethernet veth, while
# preserving the same route form used by a point-to-point tunnel.
PEER_MAC=$(ip netns exec "$REMOTE" cat /sys/class/net/afawgp/address)
ip -n "$ROUTER" neigh add 203.0.113.77 lladdr "$PEER_MAC" nud permanent dev afawg
ip -n "$ROUTER" route add default dev afawg table 16866
ip -n "$ROUTER" rule add priority 101 oif afawg lookup 16866
ip -n "$ROUTER" rule add priority 102 oif afawg prohibit
ip -n "$ROUTER" -6 route add default via fd00:1::2 dev afwan
ip -n "$ROUTER" -6 route add default via fd00:2::2 dev afawg table 16866
ip -n "$ROUTER" -6 rule add priority 101 oif afawg lookup 16866
ip -n "$ROUTER" -6 rule add priority 102 oif afawg prohibit
ip -n "$ROUTER" -6 route get 2001:db8:100::1 | grep -q 'dev afwan'
ip -n "$ROUTER" -6 route get 2001:db8:100::1 oif afawg mark 0x08000000 | grep -q 'dev afawg'

cat > "$WORK/server.py" <<'PY'
import socket, sys
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('203.0.113.77', 19277)); s.listen(4); s.settimeout(12)
open(sys.argv[1], 'w').close()
for _ in range(4):
    c, addr = s.accept()
    c.sendall(addr[0].encode()); c.close()
s.close()
PY
ip netns exec "$REMOTE" python3 "$WORK/server.py" "$WORK/ready" &
SERVER=$!
i=0
while [ ! -e "$WORK/ready" ]; do
    i=$((i+1))
    [ "$i" -lt 50 ] || { kill "$SERVER" 2>/dev/null || true; exit 1; }
    sleep 0.1
done
cat > "$WORK/client.py" <<'PY'
import socket, sys
s = socket.socket(); s.settimeout(5)
if sys.argv[1] == 'awg':
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b'afawg\0')
    s.setsockopt(socket.SOL_SOCKET, socket.SO_MARK, 0x08000000)
s.connect(('203.0.113.77', 19277))
src = s.recv(100).decode(); s.close()
assert src == sys.argv[2], f'Unexpected route: source {src}'
PY
ip netns exec "$ROUTER" python3 "$WORK/client.py" wan 192.0.2.1
ip netns exec "$ROUTER" python3 "$WORK/client.py" awg 198.51.100.1
# IPv4 may synthesize an on-link route for a socket bound to a device even
# after a prohibit rule returns an error. Verify actual sockets and the
# interface selected, rather than assuming the routing lookup must fail.
ip -n "$ROUTER" route del default table 16866
ip netns exec "$ROUTER" python3 "$WORK/client.py" awg 198.51.100.1
ip netns exec "$ROUTER" python3 "$WORK/client.py" wan 192.0.2.1
wait "$SERVER"
SERVER=''
ip -n "$ROUTER" route get 203.0.113.77 | grep -q 'dev afwan'
ip -n "$ROUTER" -6 route del default table 16866
# Record IPv6 behavior; this test does not claim IPv6 fail-closed behavior.
ip -n "$ROUTER" -6 route get 2001:db8:100::1 oif afawg mark 0x08000000 || true
ip -n "$ROUTER" -6 route get 2001:db8:100::1 | grep -q 'dev afwan'
# Observe the WAN peer directly while a socket is bound to the AWG device.
# Sending may report success on a down UDP interface, so the test must check
# what actually arrives, not only the result of sendto().
ip -n "$REMOTE" -6 addr add 2001:db8:100::1/128 dev lo nodad
cat > "$WORK/watch_udp.py" <<'PY'
import select, socket, sys, time
v4 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
v6 = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
for s in (v4, v6):
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b'afwanp\0')
v6.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
v4.bind(('0.0.0.0', 19555)); v6.bind(('::', 19555))
open(sys.argv[1], 'w').close()
seen = []
deadline = time.monotonic() + 4
while time.monotonic() < deadline:
    ready, _, _ = select.select([v4, v6], [], [], max(0, deadline - time.monotonic()))
    for s in ready:
        seen.append(s.recvfrom(1024)[0].decode())
open(sys.argv[2], 'w').write('\n'.join(seen))
PY
ip netns exec "$REMOTE" python3 "$WORK/watch_udp.py" "$WORK/udp-ready" "$WORK/udp-seen" &
SERVER=$!
i=0
while [ ! -e "$WORK/udp-ready" ]; do
    i=$((i+1)); [ "$i" -lt 50 ] || exit 1
    sleep 0.1
done
cat > "$WORK/send_udp.py" <<'PY'
import socket, sys
family = socket.AF_INET if sys.argv[1] == '4' else socket.AF_INET6
s = socket.socket(family, socket.SOCK_DGRAM)
if sys.argv[2] != 'baseline':
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b'afawg\0')
        s.setsockopt(socket.SOL_SOCKET, socket.SO_MARK, 0x08000000)
    except OSError:
        sys.exit(0) # The interface has disappeared; no packet can be sent.
destination = ('203.0.113.77', 19555) if family == socket.AF_INET else ('2001:db8:100::1', 19555)
try: s.sendto((sys.argv[2] + sys.argv[1]).encode(), destination)
except OSError: pass
PY
ip netns exec "$ROUTER" python3 "$WORK/send_udp.py" 4 baseline
ip netns exec "$ROUTER" python3 "$WORK/send_udp.py" 6 baseline
ip -n "$ROUTER" link set afawg down
ip netns exec "$ROUTER" python3 "$WORK/send_udp.py" 4 down
ip netns exec "$ROUTER" python3 "$WORK/send_udp.py" 6 down
ip -n "$ROUTER" link del afawg
ip netns exec "$ROUTER" python3 "$WORK/send_udp.py" 4 deleted
ip netns exec "$ROUTER" python3 "$WORK/send_udp.py" 6 deleted
wait "$SERVER"
SERVER=''
grep -qx baseline4 "$WORK/udp-seen"
grep -qx baseline6 "$WORK/udp-seen"
if grep -Eq '^(down|deleted)[46]$' "$WORK/udp-seen"; then
    echo 'Bound UDP packet escaped through WAN during interface failure' >&2
    exit 1
fi
echo 'No bound UDP packets observed on WAN after interface down or deletion'
echo 'Bound IPv4 sockets use the dedicated interface; ordinary sockets use WAN, including after route deletion'
