#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
LIB="$ROOT/forkop/files/usr/lib"
printf '%s\n' '{"outbounds":[]}' > "$WORK/old.json"
printf '%s\n' '{"outbounds":[],"skipped":2,"skip_reasons":{"invalid_parameters":2}}' > "$WORK/new.json"
FORKOP_SUBSCRIPTION_UPDATE_STATE_DIR="$WORK/state" \
FORKOP_SUBSCRIPTION_REPORT_JOB_ID="fixture-job" \
ucode -L "$LIB" "$LIB/subscription/cache.uc" change-report-fixture "$WORK/old.json" "$WORK/new.json"
python3 - "$WORK/state/last-report.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    report = json.load(f)
assert report['job_id'] == 'fixture-job'
sources = report['sources']
assert [s['status'] for s in sources] == ['updated', 'unchanged', 'failed']
assert [s['source'] for s in sources] == [1, 2, 3]
assert sources[0]['section'] == 'test_rule' and sources[0]['skipped'] == 2
assert sources[0]['skip_reasons']['invalid_parameters'] == 2
assert sources[2]['section'] == '[rule hidden]'
PY
echo 'Subscription report runtime checks passed'
