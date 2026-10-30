#!/usr/bin/env bash
# Integration fixture: real downloader and immutable stores; simulated tunnel.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -R "$ROOT/forkop/files/usr/lib" "$WORK/lib"
mkdir -p "$WORK/bin" "$WORK/singbox" "$WORK/state" "$WORK/persistent"
chmod 700 "$WORK" "$WORK/singbox" "$WORK/state" "$WORK/persistent"
export FORKOP_LIB="$WORK/lib" FORKOP_UCI_STATE_FILE="$WORK/uci.state"
export TMP_SING_BOX_FOLDER="$WORK/singbox" FORKOP_RUNTIME_STATE_DIR="$WORK/state"
export FORKOP_PERSISTENT_SUBSCRIPTION_CACHE_DIR="$WORK/persistent"
export FORKOP_AWG_CANDIDATE_DIR="$WORK/candidate" FORKOP_AWG_ACTIVE_DIR="$WORK/active"
export FORKOP_AWG_LAST_GOOD_DIR="$WORK/good" FORKOP_AWG_STATUS_DIR="$WORK/status"
export FORKOP_AWG_GENERATION_DIR="$WORK/generation" FORKOP_AWG_LEGACY_DIR="$WORK/legacy"
export TEST_FEED="$WORK/feed" PATH="$WORK/bin:$PATH"
cat > "$WORK/lib/subscription/amnezia_feature.uc" <<'UC'
return {enabled:function() { return true; }};
UC
cat > "$WORK/lib/uci.uc" <<'UC'
return {cursor:function() { return {load:function() { return true; }}; }};
UC
cat > "$WORK/lib/subscription/amnezia_batch.uc" <<'UC'
let store=require('subscription.amnezia_store'), active=require('subscription.amnezia_active');
function activate(dir, active_dir, good_dir, source, identity, timeout, opts) {
  if (getenv('TEST_FAIL_ACTIVATION') == '1') return {ok:false};
  let rev=store.revision(dir,source,identity);
  if (!store.promote(dir,good_dir,source,identity,rev) ||
      !active.save(active_dir,source,identity,rev,[{index:0,name:'afawg_1',table:'15001',priority:'16002'}],function(){return true;})) return {ok:false};
  return {ok:opts.publish(rev) === true};
}
return {activate};
UC
cat > "$WORK/lib/subscription/amnezia_generation_migrate.uc" <<'UC'
let status=require('subscription.amnezia_status'), gen=require('subscription.amnezia_generation');
function migrate(sd,ad,gd,dir,source,cursor,timeout,opts) {
 let s=status.read(sd,source);
 if (!s || !opts.current()) return false;
 let r={version:1,kind:'subscription',mode:s.mode,source,identity:s.identity,revision:s.revision,url:s.url,user_agent:s.user_agent,hwid:s.hwid,legacy_revision:s.legacy_revision,entries:[{index:0,name:'afawg_1',table:'15001',priority:'16002'}]};
 let id=gen.stage(dir,gd,r,function(){return true;});
 return id != null && gen.switch_to(dir,source,null,id);
}
return {migrate};
UC
cat > "$WORK/bin/curl" <<'SH'
#!/bin/sh
out= headers=
while [ "$#" -gt 0 ]; do
 case "$1" in -o) out=$2; shift;; -D) headers=$2; shift;; esac
 shift
done
test -n "$out" || exit 1
cp "$TEST_FEED" "$out"
[ -z "$headers" ] || printf 'HTTP/1.1 200 OK\r\n\r\n' > "$headers"
SH
cat > "$WORK/bin/logger" <<'SH'
#!/bin/sh
exit 0
SH
cat > "$WORK/bin/sing-box" <<'SH'
#!/bin/sh
echo 'sing-box version 1.14.3-extended-2.7.3'
SH
chmod +x "$WORK/bin/"*
cat > "$WORK/uci.state" <<'STATE'
forkop.settings=settings
forkop.test=section
forkop.test.enabled=1
forkop.test.action=connection
forkop.test.subscription_urls=https://example.invalid/sub
STATE
key='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
printf '[Interface]\nPrivateKey = %s\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = %s\nEndpoint = example.invalid:443\nAllowedIPs = 0.0.0.0/0\n' "$key" "$key" > "$WORK/profile"
{
 printf 'vless://11111111-1111-4111-8111-111111111111@example.invalid:443?type=tcp#first\n'
 printf 'vpn://'; base64 < "$WORK/profile" | tr -d '\n'; printf '\n'
} > "$TEST_FEED"
run_update() { ucode -L "$FORKOP_LIB" "$FORKOP_LIB/subscription/cache.uc" update-source test 1 https://example.invalid/sub runtime; }
run_update
test -s "$WORK/generation/test-subscription-1.current"
test -s "$WORK/singbox/subscriptions/test-subscription-1.json"
cp "$WORK/generation/test-subscription-1.current" "$WORK/pointer-before"
cp "$WORK/singbox/subscriptions/test-subscription-1.json" "$WORK/legacy-before"
printf 'vpn://invalid\n' >> "$TEST_FEED"
if run_update; then echo 'invalid AWG accepted' >&2; exit 1; fi
cmp "$WORK/pointer-before" "$WORK/generation/test-subscription-1.current"
cmp "$WORK/legacy-before" "$WORK/singbox/subscriptions/test-subscription-1.json"
echo 'mixed downloader fixture passed'
