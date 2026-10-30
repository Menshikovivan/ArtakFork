#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
LIB="$ROOT/forkop/files/usr/lib"
mkdir "$WORK/tmp"
cat > "$WORK/good.conf" <<'EOF'
[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.8.1.2/32
Jc = 4
Jmin = 40
Jmax = 70
[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
AllowedIPs = 0.0.0.0/0
Endpoint = awg.example.invalid:10444
EOF
VPN="vpn://$(base64 < "$WORK/good.conf" | tr -d '\n')"
printf '%s\n' "$VPN" | base64 | tr -d '\n' > "$WORK/only"
printf '%s\n%s\n' 'vless://example.invalid' "$VPN" | base64 | tr -d '\n' > "$WORK/mixed"
printf '%s\n' 'vpn://malformed!' > "$WORK/bad"
stage() {
  TMP_SUBSCRIPTION_FOLDER="$WORK/tmp" FORKOP_AWG_CANDIDATE_DIR="$WORK/candidates" FORKOP_AWG_STAGE_CANDIDATES=1 \
    ucode -L "$LIB" "$LIB/subscription/cache.uc" stage-amnezia-candidate-fixture "$1" test_1 \
    'https://example.invalid/sub' 'test-agent' ''
}
if TMP_SUBSCRIPTION_FOLDER="$WORK/tmp" FORKOP_AWG_CANDIDATE_DIR="$WORK/candidates" \
  ucode -L "$LIB" "$LIB/subscription/cache.uc" stage-amnezia-candidate-fixture "$WORK/only" test_1 \
    'https://example.invalid/sub' 'test-agent' ''; then
  echo 'FAIL: candidate staging accepted without opt-in' >&2; exit 1
fi
[ ! -e "$WORK/candidates/test_1.awg.json" ]
stage "$WORK/only"
[ -s "$WORK/candidates/test_1.awg.json" ]
[ "$(stat -c %a "$WORK/candidates")" = 700 ]
[ "$(stat -c %a "$WORK/candidates/test_1.awg.json")" = 600 ]
stage "$WORK/mixed"
cp "$WORK/candidates/test_1.awg.json" "$WORK/previous"
if stage "$WORK/bad"; then echo 'FAIL: invalid candidate accepted' >&2; exit 1; fi
cmp "$WORK/previous" "$WORK/candidates/test_1.awg.json"
test -z "$(find "$WORK/tmp" -type f -print)"
echo 'AWG-only and mixed feed candidates staged privately; invalid update retained'
