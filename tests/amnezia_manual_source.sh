#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export ARTAK_AWG_MANUAL_TEST_DIR="$WORK"
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_manual_source.uc"
