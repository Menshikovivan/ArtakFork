#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_swap.uc"
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_guard_union.uc"
