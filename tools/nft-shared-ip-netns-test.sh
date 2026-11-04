#!/bin/sh
# Isolated synthetic nft experiment. Never touches the production nft ruleset.
# Requires: root, ip-full with netns support, nft, wget, kernel network namespaces.
set -eu
[ "$(id -u)" = 0 ] || { echo 'SKIP: root required'; exit 77; }
command -v ip >/dev/null && command -v nft >/dev/null && command -v wget >/dev/null || {
  echo 'SKIP: ip, nft and wget required'; exit 77;
}
work=$(mktemp -d /tmp/artak-nft-test.XXXXXX)
nsr="artak-r-$$"
nsc="artak-c-$$"
made_r=0
made_c=0
cleanup() {
  [ "$made_c" = 0 ] || ip netns del "$nsc" >/dev/null 2>&1 || true
  [ "$made_r" = 0 ] || ip netns del "$nsr" >/dev/null 2>&1 || true
  rm -f "$work/rules.nft" "$work/counter" "$work/batch.nft" "$work/pin-table.nft"
  rmdir "$work" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
if ! ip netns add "$nsr" 2>/dev/null; then
  echo 'SKIP: cannot create network namespaces'; exit 77
fi
made_r=1
if ! ip netns add "$nsc" 2>/dev/null; then
  echo 'SKIP: cannot create second network namespace'; exit 77
fi
made_c=1
ip -n "$nsr" link add artak-r type veth peer name artak-c
ip -n "$nsr" link set artak-c netns "$nsc"
ip -n "$nsr" addr add 10.243.92.1/30 dev artak-r
ip -n "$nsc" addr add 10.243.92.2/30 dev artak-c
ip -n "$nsr" link set lo up
ip -n "$nsc" link set lo up
ip -n "$nsr" link set artak-r up
ip -n "$nsc" link set artak-c up
ip -n "$nsc" route add 203.0.113.0/24 via 10.243.92.1
cat >"$work/rules.nft" <<'EOF'
table inet artak_shared_test {
  set section_a { type ipv4_addr; flags interval; elements = { 203.0.113.1, 203.0.113.3, 203.0.113.4, 203.0.113.5 } }
  set section_b { type ipv4_addr; flags interval; elements = { 203.0.113.2, 203.0.113.3 } }
  set section_c_subnets { type ipv4_addr; flags interval; elements = { 203.0.113.4/31 } }
  counter unique_a {}
  counter unique_b {}
  counter shared {}
  counter subnet_shared {}
  counter unmarked {}
  chain check {
    type filter hook prerouting priority mangle; policy accept;
    iifname "artak-r" ip daddr != 203.0.113.4 meta mark set 0x04000000
    meta mark & 0x04000000 == 0 ip daddr @section_a counter name unmarked accept
    meta mark & 0x04000000 == 0x04000000 ip daddr @section_a ip daddr @section_b counter name shared accept
    meta mark & 0x04000000 == 0x04000000 ip daddr @section_a ip daddr @section_c_subnets counter name subnet_shared accept
    meta mark & 0x04000000 == 0x04000000 ip daddr @section_a ip daddr != @section_b ip daddr != @section_c_subnets counter name unique_a accept
    meta mark & 0x04000000 == 0x04000000 ip daddr @section_b ip daddr != @section_a ip daddr != @section_c_subnets counter name unique_b accept
  }
}
EOF
ip netns exec "$nsr" nft -c -f "$work/rules.nft"
ip netns exec "$nsr" nft -f "$work/rules.nft"
for ipaddr in 203.0.113.1 203.0.113.2 203.0.113.3 203.0.113.4 203.0.113.5; do
  ip netns exec "$nsc" env http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= all_proxy= \
    wget -T 2 -q -O /dev/null "http://$ipaddr/" >/dev/null 2>&1 || true
done
for counter in unique_a unique_b shared subnet_shared unmarked; do
  ip netns exec "$nsr" nft list counter inet artak_shared_test "$counter" >"$work/counter"
  if ! grep -Eq 'packets[[:space:]]+[1-9][0-9]*' "$work/counter"; then
    echo "FAIL: $counter did not receive expected synthetic traffic"
    cat "$work/counter"
    exit 1
  fi
  echo "PASS: $counter"
done
cat >"$work/batch.nft" <<'EOF'
add rule inet artak_shared_test check counter comment "artak-batch-rollback-probe"
add rule inet artak_shared_test check ip daddr @missing_set counter
EOF
if ip netns exec "$nsr" nft -f "$work/batch.nft" >/dev/null 2>&1; then
  echo 'FAIL: invalid nft batch unexpectedly succeeded'; exit 1
fi
if ip netns exec "$nsr" nft list chain inet artak_shared_test check | grep -Fq 'artak-batch-rollback-probe'; then
  echo 'FAIL: nft applied part of rejected batch'; exit 1
fi
echo 'PASS: invalid nft batch left no partial rule'
echo 'add rule inet artak_shared_test check counter comment "artak-batch-success-probe"' >"$work/batch.nft"
ip netns exec "$nsr" nft -f "$work/batch.nft"
ip netns exec "$nsr" nft list chain inet artak_shared_test check | grep -Fq 'artak-batch-success-probe' || {
  echo 'FAIL: valid nft batch was not applied'; exit 1;
}
echo 'PASS: valid nft batch applied'
if [ -n "${ARTAK_PIN_BATCH:-}" ]; then
  cat >"$work/pin-table.nft" <<'EOF'
table inet forkop {
  set lan { type ifname; elements = { "artak-r" } }
  set forkop_rule_a_resolved { type ipv4_addr; }
  set forkop_rule_a_resolved6 { type ipv6_addr; }
  chain proxy { type filter hook prerouting priority -100; policy accept; }
}
EOF
  ip netns exec "$nsr" nft -f "$work/pin-table.nft"
  if ip netns exec "$nsr" nft -f "$ARTAK_PIN_BATCH" >/dev/null 2>&1; then
    echo 'FAIL: generated pin batch accepted missing competitor set'; exit 1
  fi
  if ip netns exec "$nsr" nft list chain inet forkop proxy | grep -Fq tproxy; then
    echo 'FAIL: rejected generated pin batch was partially applied'; exit 1
  fi
  ip netns exec "$nsr" nft add set inet forkop forkop_rule_b_resolved '{ type ipv4_addr; }'
  ip netns exec "$nsr" nft add set inet forkop forkop_rule_b_resolved6 '{ type ipv6_addr; }'
  ip netns exec "$nsr" nft -c -f "$ARTAK_PIN_BATCH"
  ip netns exec "$nsr" nft -f "$ARTAK_PIN_BATCH"
  ip netns exec "$nsr" nft list chain inet forkop proxy > "$work/counter"
  [ "$(grep -c tproxy "$work/counter")" = 2 ] || { echo 'FAIL: expected two generated pin rules'; exit 1; }
  first=$(grep tproxy "$work/counter" | head -1)
  case "$first" in *ip6*) ;; *) echo 'FAIL: unexpected nft insert order'; exit 1 ;; esac
  echo 'PASS: generated IPv4/IPv6 pin batch atomicity and insert order'
fi
echo 'PASS: isolated nft shared-IP set and mark experiment'
echo 'NOTE: this tests nft set logic, not Xray sniffing, IPv6 or live pinning.'
