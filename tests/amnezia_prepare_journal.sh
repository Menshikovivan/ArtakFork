#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_prepare_journal.uc" "$WORK"
[ "$(stat -c %a "$WORK/prepare/source.prepare.json")" = 600 ]
