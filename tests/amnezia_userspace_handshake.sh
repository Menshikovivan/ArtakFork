#!/bin/sh
# Real userspace AWG peers in isolated network namespaces. Synthetic keys only.
# This does not exercise OpenWrt netifd, kernel module, or router packages.
set -eu
umask 077
[ "$#" -eq 2 ] || { echo 'Usage: test AWG_TOOL AWG_GO' >&2; exit 2; }
TOOL=$(realpath "$1"); ENGINE=$(realpath "$2")
[ -x "$TOOL" ] && [ -x "$ENGINE" ] && [ -c /dev/net/tun ] || { echo 'Missing AWG binaries or /dev/net/tun' >&2; exit 1; }
WORK=$(mktemp -d /tmp/artak-awg-handshake.XXXXXXXX)
NA="atna$$"; NB="atnb$$"; IA="ata$$"; IB="atb$$"; PA=''; PB=''
cleanup() {
    [ -z "$PA" ] || kill "$PA" 2>/dev/null || true
    [ -z "$PB" ] || kill "$PB" 2>/dev/null || true
    [ -z "$PA" ] || wait "$PA" 2>/dev/null || true
    [ -z "$PB" ] || wait "$PB" 2>/dev/null || true
    ip netns del "$NA" 2>/dev/null || true
    ip netns del "$NB" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM
ip netns add "$NA"; ip netns add "$NB"
ip -n "$NA" link add awga type veth peer name awgb netns "$NB"
ip -n "$NA" addr add 192.0.2.1/24 dev awga
ip -n "$NB" addr add 192.0.2.2/24 dev awgb
ip -n "$NA" link set lo up; ip -n "$NB" link set lo up
ip -n "$NA" link set awga up; ip -n "$NB" link set awgb up
ip netns exec "$NA" "$ENGINE" -f "$IA" >"$WORK/a.log" 2>&1 & PA=$!
ip netns exec "$NB" "$ENGINE" -f "$IB" >"$WORK/b.log" 2>&1 & PB=$!
i=0
while [ ! -S "/var/run/amneziawg/$IA.sock" ] || [ ! -S "/var/run/amneziawg/$IB.sock" ]; do
    kill -0 "$PA" 2>/dev/null && kill -0 "$PB" 2>/dev/null || { echo 'AWG userspace engine failed to start' >&2; exit 1; }
    i=$((i+1)); [ "$i" -lt 100 ] || { echo 'AWG userspace startup timed out' >&2; exit 1; }
    sleep 0.1
done
ip -n "$NA" addr add 10.88.0.1/24 dev "$IA"
ip -n "$NB" addr add 10.88.0.2/24 dev "$IB"
ip -n "$NA" link set "$IA" up; ip -n "$NB" link set "$IB" up
"$TOOL" genkey > "$WORK/a.key"; "$TOOL" pubkey < "$WORK/a.key" > "$WORK/a.pub"
"$TOOL" genkey > "$WORK/b.key"; "$TOOL" pubkey < "$WORK/b.key" > "$WORK/b.pub"
"$TOOL" genkey > "$WORK/header.key"
ak=$(cat "$WORK/a.key"); bk=$(cat "$WORK/b.key"); ap=$(cat "$WORK/a.pub"); bp=$(cat "$WORK/b.pub"); hk=$(cat "$WORK/header.key")
run_profile() {
    mode=$1
    # 2.0 uses range H1–H4 and S3/S4; 3.1 exercises header protection,
    # RandomTrailers, and DisableCookies with standard message identifiers.
    if [ "$mode" = 2.0 ]; then
        extra='H1=101-110
H2=201-210
H3=301-310
H4=401-410'
    else
        extra="H1=1
H2=2
H3=3
H4=4
HeaderProtectionKey=$hk
RandomTrailers=on
DisableCookies=on"
    fi
    printf '[Interface]\nPrivateKey=%s\nListenPort=29001\nJc=4\nJmin=40\nJmax=70\nS1=16\nS2=16\nS3=16\nS4=16\n%s\n[Peer]\nPublicKey=%s\nAllowedIPs=10.88.0.2/32\nEndpoint=192.0.2.2:29002\nPersistentKeepalive=2\n' "$ak" "$extra" "$bp" > "$WORK/a.conf"
    printf '[Interface]\nPrivateKey=%s\nListenPort=29002\nJc=4\nJmin=40\nJmax=70\nS1=16\nS2=16\nS3=16\nS4=16\n%s\n[Peer]\nPublicKey=%s\nAllowedIPs=10.88.0.1/32\nEndpoint=192.0.2.1:29001\nPersistentKeepalive=2\n' "$bk" "$extra" "$ap" > "$WORK/b.conf"
    # setconf can echo an invalid config line on error. Files contain only
    # freshly generated disposable keys; never print their contents.
    ip netns exec "$NA" "$TOOL" setconf "$IA" "$WORK/a.conf" >"$WORK/set-a.log" 2>&1 || { echo "AWG $mode setup A failed" >&2; exit 1; }
    ip netns exec "$NB" "$TOOL" setconf "$IB" "$WORK/b.conf" >"$WORK/set-b.log" 2>&1 || { echo "AWG $mode setup B failed" >&2; exit 1; }
    ip netns exec "$NA" ping -q -c 5 -w 12 10.88.0.2 >/dev/null || { echo "AWG $mode ping failed" >&2; exit 1; }
    ip netns exec "$NB" ping -q -c 2 -w 8 10.88.0.1 >/dev/null || { echo "AWG $mode reverse ping failed" >&2; exit 1; }
    for pair in "$NA $IA" "$NB $IB"; do
        set -- $pair
        stamp=$(ip netns exec "$1" "$TOOL" show "$2" latest-handshakes | awk 'NR==1 {print $2}')
        case "$stamp" in ''|*[!0-9]*|0) echo "AWG $mode handshake absent" >&2; exit 1;; esac
        age=$(( $(date +%s) - stamp )); [ "$age" -ge 0 ] && [ "$age" -le 30 ] || { echo "AWG $mode handshake stale" >&2; exit 1; }
    done
    echo "AWG $mode: bidirectional ping and fresh handshakes passed"
}
run_profile 2.0
# Fresh peers/keys ensure the 3.1 assertion cannot reuse a 2.0 handshake.
"$TOOL" genkey > "$WORK/a.key"; "$TOOL" pubkey < "$WORK/a.key" > "$WORK/a.pub"
"$TOOL" genkey > "$WORK/b.key"; "$TOOL" pubkey < "$WORK/b.key" > "$WORK/b.pub"
ak=$(cat "$WORK/a.key"); bk=$(cat "$WORK/b.key"); ap=$(cat "$WORK/a.pub"); bp=$(cat "$WORK/b.pub")
run_profile 3.1
