#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ARTAK_TEST_UCI_DIR=$(mktemp -d /tmp/artak-uci-test.XXXXXXXX)
export ARTAK_TEST_UCI_DIR
trap 'rm -rf "$ARTAK_TEST_UCI_DIR"' EXIT HUP INT TERM
mkdir "$ARTAK_TEST_UCI_DIR/delta" "$ARTAK_TEST_UCI_DIR/delta2"
printf "config interface 'wan'\n\toption proto 'dhcp'\n" > "$ARTAK_TEST_UCI_DIR/network"
printf "config settings 'settings'\nconfig rule 'rule1'\n\toption action 'connection'\n" > "$ARTAK_TEST_UCI_DIR/forkop"
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_import_real_uci.uc"
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_manual_worker_real_uci.uc"
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_apply_real_uci.uc"
