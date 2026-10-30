#!/bin/sh
# Isolated proof of a possible marked-socket fail-closed guard. This is NOT
# installed in Forkop and does not test netifd, reboot, or AWG encryption.
set -eu
R="afguard$$"; P="afguardpeer$$"; WORK=$(mktemp -d); SERVER=''
cleanup() {
    [ -z "$SERVER" ] || kill "$SERVER" 2>/dev/null || true
    ip netns del "$R" 2>/dev/null || true
    ip netns del "$P" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM
ip netns add "$R"
ip netns add "$P"
ip -n "$R" link add afwan type veth peer name afwanp netns "$P"
ip -n "$R" link set lo up
ip -n "$P" link set lo up
ip -n "$R" link set afwan up
ip -n "$P" link set afwanp up
ip -n "$R" addr add 192.0.2.1/24 dev afwan
ip -n "$P" addr add 192.0.2.2/24 dev afwanp
ip -n "$R" -6 addr add fd00:1::1/64 dev afwan nodad
ip -n "$P" -6 addr add fd00:1::2/64 dev afwanp nodad
ip netns exec "$R" nft add table inet artak_guard
ip netns exec "$R" nft 'add chain inet artak_guard output { type filter hook output priority filter; policy accept; }'
ip netns exec "$R" nft 'add rule inet artak_guard output meta mark 0x09000001 oifname != "afawg_a" counter drop'
cat > "$WORK/server.py" <<'PY'
import select, socket, sys, time
s4 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s4.bind(('192.0.2.2', 19556))
s6 = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM); s6.bind(('fd00:1::2', 19556))
open(sys.argv[1], 'w').close(); seen = []
deadline = time.monotonic() + 3
while time.monotonic() < deadline:
    ready, _, _ = select.select([s4, s6], [], [], deadline - time.monotonic())
    for s in ready: seen.append(s.recvfrom(256)[0].decode())
open(sys.argv[2], 'w').write('\n'.join(seen))
PY
ip netns exec "$P" python3 "$WORK/server.py" "$WORK/ready" "$WORK/seen" & SERVER=$!
i=0
while [ ! -e "$WORK/ready" ]; do i=$((i+1)); [ "$i" -lt 50 ] || exit 1; sleep 0.1; done
cat > "$WORK/client.py" <<'PY'
import socket, sys
family = socket.AF_INET if sys.argv[1] == '4' else socket.AF_INET6
s = socket.socket(family, socket.SOCK_DGRAM)
if sys.argv[2] == 'marked': s.setsockopt(socket.SOL_SOCKET, socket.SO_MARK, 0x09000001)
try: s.sendto((sys.argv[2] + sys.argv[1]).encode(), ('192.0.2.2' if family == socket.AF_INET else 'fd00:1::2', 19556))
except OSError: pass
PY
for family in 4 6; do
    ip netns exec "$R" python3 "$WORK/client.py" "$family" baseline
    ip netns exec "$R" python3 "$WORK/client.py" "$family" marked
done
wait "$SERVER"; SERVER=''
grep -qx baseline4 "$WORK/seen"
grep -qx baseline6 "$WORK/seen"
if grep -q '^marked' "$WORK/seen"; then echo 'FAIL: AWG-marked packet reached WAN' >&2; exit 1; fi
echo 'Dedicated-mark guard blocked WAN packets in IPv4 and IPv6'
