#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/awg" "$WORK/subscriptions" "$WORK/status"
TMP_SUBSCRIPTION_FOLDER="$WORK/subscriptions" FORKOP_AWG_STATUS_DIR="$WORK/status" ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_store.uc" "$WORK/awg" "$WORK/subscriptions" "$WORK/status"
[ "$(stat -c %a "$WORK/awg")" = 700 ]
[ "$(stat -c %a "$WORK/awg/rule_1.awg.json")" = 600 ]
[ "$(stat -c %a "$WORK/awg/last-good")" = 700 ]
find "$WORK/awg/last-good" -name '*.awg.json' -type f -exec stat -c %a {} \; | grep -qx 600
echo 'AWG private cache permissions verified'
