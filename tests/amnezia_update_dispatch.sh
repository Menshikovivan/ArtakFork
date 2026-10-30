#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/queue"
touch "$WORK/queue/rule-subscription-1.request.json"
cat > "$WORK/test.uc" <<'EOF'
let fs = require('fs');
let LIB_DIR = '/test/lib', RELOAD_LOCK_DIR = 'reload', SUBSCRIPTION_UPDATE_LOCK_DIR = 'subscription';
let AWG_SWAP_DISPATCH_ENABLED = true;
let events = [], held = {}, fail_job = false, recorded = null, subscription_outbounds_changed = false;
function feature_enabled() { return true; }
function as_string(v) { return '' + v; }
function subscription_cache_success(x) { return true; }
function acquire_runtime_lock(name, force) { push(events, 'acquire:' + name); held[name] = true; return true; }
function release_runtime_lock(name) { push(events, 'release:' + name); held[name] = false; }
function subscription_update_common_locked(force, section, index) { push(events, 'update'); return true; }
function subscription_record_result(ok, target) { recorded = ok; }
function run_pending_reload_if_requested() {}
function module_background(args) { return true; }
function mark_pending_reload(reason) {}
function log_message(message, level) {}
function module_status(args) {
    if (held.reload || held.subscription || args[1] != 'awg-swap-job' || args[2] != 'rule-subscription-1') die('job ran with locks or wrong source\n');
    push(events, 'job'); return fail_job ? 1 : 0;
}
EOF
sed -n '/^function run_pending_awg_swap_jobs()/,/^}/p; /^function subscription_update_common(force,/,/^}/p' "$ROOT/forkop/files/usr/lib/components/updates.uc" | \
    sed "s/require('subscription.amnezia_feature').enabled()/feature_enabled()/g" >> "$WORK/test.uc"
cat >> "$WORK/test.uc" <<'EOF'
function expect(v, m) { if (!v) die('FAIL: ' + m + '\n'); }
expect(subscription_update_common(true, '', '') == 0 && recorded === true, 'successful update failed');
expect(join(',', events) == 'acquire:reload,acquire:subscription,update,release:subscription,release:reload,job', 'lock order or dispatch');
events = []; fail_job = true; recorded = null;
expect(subscription_update_common(true, '', '') == 1 && recorded === false, 'failed job reported success');
expect(join(',', events) == 'acquire:reload,acquire:subscription,update,release:subscription,release:reload,job', 'failed job order');
events = []; fail_job = false; recorded = null; AWG_SWAP_DISPATCH_ENABLED = false;
expect(subscription_update_common(true, '', '') == 1 && recorded === false && index(join(',', events), 'job') < 0,
    'unverified production dispatch was not disabled');
print('AWG queued job dispatched after real update lock flow checks passed\n');
EOF
FORKOP_AWG_SWAP_QUEUE_DIR="$WORK/queue" ucode "$WORK/test.uc"
