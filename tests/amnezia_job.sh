#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export ARTAK_AWG_JOB_TEST_DIR="$WORK/job"
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/tests/amnezia_job.uc"
mkdir "$WORK/target"
ln -s "$WORK/target" "$WORK/link"
export ARTAK_AWG_JOB_TEST_DIR="$WORK/link"
ucode -L "$ROOT/forkop/files/usr/lib" -e '
let job = require("subscription.amnezia_job");
let k = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
let c = "[Interface]\nPrivateKey = " + k + "\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = " + k + "\nEndpoint = example.com:443\nAllowedIPs = 0.0.0.0/0\n";
if (job.start(c, function() { return true; }).ok) die("symlink root accepted\n");
'
[ ! -e "$WORK/target/input" ]
