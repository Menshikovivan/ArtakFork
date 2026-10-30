#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/artak-awg-nft.XXXXXXXX)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
export ARTAK_SNAPSHOT_TEST_DIR="$WORK/snapshot"
mkdir "$ARTAK_SNAPSHOT_TEST_DIR"
REVISION=$(ucode -L "$ROOT/forkop/files/usr/lib" -e '
let s=require("subscription.amnezia_snapshot");
let result=s.save(getenv("ARTAK_SNAPSHOT_TEST_DIR"), [{index:0,name:"afawg_a",table:"16866",priority:"1000",mark:0x18000000 | 16866,source:"test",identity:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",revision:"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]);
if (!result) die("snapshot failed\n"); print(result.revision);
')
export FORKOP_NFT_BATCH_FILE="$WORK/candidate.nft"
printf '# candidate\n' > "$FORKOP_NFT_BATCH_FILE"
ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/forkop/files/usr/lib/nft/apply.uc" nft-add-awg-guards ForkopTable "$ARTAK_SNAPSHOT_TEST_DIR" "$REVISION"
grep -Fq 'insert rule inet ForkopTable mangle_output meta mark == 0x180041e2 oifname != "afawg_a" counter drop' "$FORKOP_NFT_BATCH_FILE"
cp "$FORKOP_NFT_BATCH_FILE" "$WORK/before"
if ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/forkop/files/usr/lib/nft/apply.uc" nft-add-awg-guards ForkopTable "$ARTAK_SNAPSHOT_TEST_DIR" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; then
    echo 'Modified snapshot revision accepted' >&2; exit 1
fi
cmp "$WORK/before" "$FORKOP_NFT_BATCH_FILE"
if FORKOP_NFT_CANDIDATE_FAIL_PHASE=prepare ucode -L "$ROOT/forkop/files/usr/lib" "$ROOT/forkop/files/usr/lib/nft/apply.uc" nft-add-awg-guards ForkopTable "$ARTAK_SNAPSHOT_TEST_DIR" "$REVISION"; then
    echo 'Candidate preparation failure accepted' >&2; exit 1
fi
cmp "$WORK/before" "$FORKOP_NFT_BATCH_FILE"
echo 'AWG guard is staged into the exact nft candidate snapshot'
