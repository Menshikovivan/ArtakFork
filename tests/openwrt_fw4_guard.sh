#!/bin/sh
# Run ONLY in a disposable OpenWrt VM. This exercises the real fw4 reload and
# a separate nft table. It does not install or verify the complete Forkop setup.
set -eu
[ "${ARTAK_DISPOSABLE_VM:-}" = 1 ] || { echo 'Disposable VM opt-in required' >&2; exit 2; }
command -v nft >/dev/null
command -v fw4 >/dev/null
[ -x /etc/init.d/firewall ]
NAME="artak_guard_test_$$"
WORK=$(mktemp -d)
created=0
cleanup() {
    [ "$created" = 0 ] || nft delete table inet "$NAME" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM
nft add table inet "$NAME"
created=1
nft "add chain inet $NAME output { type route hook output priority mangle; policy accept; }"
nft "add rule inet $NAME output meta mark 0x09000001 oifname != \"afawg_test\" counter drop"
nft list chain inet "$NAME" output > "$WORK/before"
/etc/init.d/firewall reload
nft list chain inet "$NAME" output > "$WORK/after"
cmp "$WORK/before" "$WORK/after"
echo 'Stock OpenWrt firewall reload retained an independent AWG-style guard table'
