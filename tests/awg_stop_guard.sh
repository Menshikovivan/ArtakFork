#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT/forkop/files/usr/lib/service/lifecycle.uc" "$WORK/stop.uc" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
body = text[text.index('function stop_main('):text.index('function finish_list_change_files(')]
prefix = '''
let calls = [], failure = false;
let STATE_UC='state', DNS_FAILOVER_UC='dns', PRIORITY_UC='priority', SUBSCRIPTION_CACHE_UC='cache', UPDATES_UC='updates';
let ZAPRET_UC='zapret', ZAPRET2_UC='zapret2', BYEDPI_UC='byedpi', NFT_UC='nft', NFT_TABLE_NAME='ForkopTable';
let RT_TABLE_NAME='100', NFT_FAKEIP_MARK='1', WATCHDOG_READY_FILE='ready', TMP_RULESET_FOLDER='tmp';
function log_message() {};
function module_success(mod, args) { push(calls, 'module:' + args[0]); return false; }
function module_status(mod, args) { push(calls, 'status:' + args[0]); return failure ? 7 : 0; }
function remove_file(path) { push(calls, 'remove:' + path); }
function remove_cron_jobs() { push(calls, 'cron'); }
function command_success_from_args(args) { push(calls, join(':', args)); return true; }
function dnsmasq_restore_fail_safe() { push(calls, 'dns-restore'); return 0; }
function mark_runtime_stopped_clean() { push(calls, 'mark-stopped'); return 0; }
function expect(v,m) { if (!v) die('FAIL: ' + m + '\\n'); }
'''
suffix = '''
failure = true;
expect(stop_main() == 7, 'failed stop propagated');
expect(index(join(' ', calls), 'nft:delete') < 0 && index(join(' ', calls), 'remove:ready') < 0, 'failed stop preserves runtime and guard');
calls = [];
expect(cleanup_failed_runtime() == 7, 'cleanup failure propagated');
expect(index(join(' ', calls), 'dns-restore') < 0 && index(join(' ', calls), 'mark-stopped') < 0, 'failed cleanup preserves DNS and state');
calls = []; failure = false;
expect(stop_main() == 0, 'successful stop');
let text = join(' ', calls);
expect(index(text, 'status:stop-managed-sing-box-runtime') >= 0 && index(text, 'nft:delete') > index(text, 'status:stop-managed-sing-box-runtime'), 'guard removed only after stop');
print('AWG guard preserved on stop failure\\n');
'''
Path(sys.argv[2]).write_text(prefix + body + suffix)
PY
ucode "$WORK/stop.uc"
