#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_generation.uc" "$WORK"
[ "$(stat -c %a "$WORK/generation/source.current")" = 600 ]
[ "$(stat -c %a "$WORK/journal5/source.swap.json")" = 600 ]
