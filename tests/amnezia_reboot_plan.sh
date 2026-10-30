#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_reboot_plan.uc"
