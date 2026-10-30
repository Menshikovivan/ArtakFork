#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/awg" "$WORK/subscriptions"
TMP_SUBSCRIPTION_FOLDER="$WORK/subscriptions" ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_store.uc" "$WORK/awg" "$WORK/subscriptions"
[ "$(stat -c %a "$WORK/awg")" = 700 ]
[ "$(stat -c %a "$WORK/awg/rule_1.awg.json")" = 600 ]
echo 'AWG private cache permissions verified'
