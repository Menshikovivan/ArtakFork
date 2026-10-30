#!/bin/sh
# Real iproute2/nft JSON in an isolated namespace. This is a representative
# subset of ArtakFork/fw4 rules, not the user's complete router configuration.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NS="afmark$$"
cleanup() { ip netns del "$NS" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM
ip netns add "$NS"
ip -n "$NS" link set lo up
ip -n "$NS" -4 rule add priority 105 fwmark 0x04000000/0x04000000 lookup 100
ip netns exec "$NS" nft add table inet artak_mark_test
ip netns exec "$NS" nft 'add chain inet artak_mark_test input { type filter hook input priority filter; policy accept; }'
ip netns exec "$NS" nft 'add rule inet artak_mark_test input ct state { established, related } counter accept'
ip netns exec "$NS" nft 'add chain inet artak_mark_test output { type route hook output priority mangle; policy accept; }'
ip netns exec "$NS" nft 'add rule inet artak_mark_test output meta mark & 0x08000000 == 0x08000000 counter return'
ip netns exec "$NS" nft 'add rule inet artak_mark_test output meta mark set 0x04000000 counter return'
audit() {
    ip netns exec "$NS" ucode -L "$ROOT/forkop/files/usr/lib" -e '
      let result=require("subscription.amnezia_mark_audit").audit([0x18003a9a]);
      if (!result.ok) { warn(result.error, "\n"); exit(1); }
    '
}
audit
ip -n "$NS" -4 rule add priority 106 fwmark 0x08000000/0x08000000 lookup 101
if audit; then echo 'FAIL: overlapping masked IP rule accepted' >&2; exit 1; fi
ip -n "$NS" -4 rule del priority 106
ip netns exec "$NS" nft 'add rule inet artak_mark_test output meta mark set meta mark | 0x04000000'
if audit; then echo 'FAIL: dynamic mark writer accepted' >&2; exit 1; fi
echo 'AWG audit accepted representative real nft JSON and rejected conflicts'
