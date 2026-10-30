#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
export ARTAK_AWG_RECOVERY_TEST_DIR="$WORK"
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_swap_recovery.uc"
