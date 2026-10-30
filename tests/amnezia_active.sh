#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/active"
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_active.uc" "$WORK/active"
[ "$(stat -c %a "$WORK/active")" = 700 ]
[ "$(stat -c %a "$WORK/active/rule_1.json")" = 600 ]
echo 'AWG active mapping permissions verified'
