#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/queue"
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_swap_queue.uc" "$WORK/queue"
[ "$(stat -c %a "$WORK/queue")" = 700 ]
