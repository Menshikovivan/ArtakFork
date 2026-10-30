#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
AWG_PENDING_TEST_DIR=$(mktemp -d)
export AWG_PENDING_TEST_DIR
trap 'rm -rf "$AWG_PENDING_TEST_DIR"' EXIT HUP INT TERM
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_pending.uc"
