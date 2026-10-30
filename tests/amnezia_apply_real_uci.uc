let uci = require('uci');
let fs = require('fs');
let apply = require('subscription.amnezia_apply');
function expect(v, m) { if (!v) die(m + '\n'); }
let dir = getenv('ARTAK_TEST_UCI_DIR');
if (type(dir) != 'string' || !match(dir, /^\/tmp\/artak-uci-test\.[A-Za-z0-9]+$/)) die('Unsafe test directory\n');
let fixture = '[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\nAddress = 10.0.0.2/32\n' +
    '[Peer]\nPublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=\nAllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example:8443\n';
let log = [], ticks = 0, fail_start = false, mutate_on_stop = false, fail_stop = false;
function runner(args) {
    push(log, args);
    if (args[5] == 'down' && fail_stop) return {ok:false};
    if (args[5] == 'down' && mutate_on_stop) {
        let other = uci.cursor(dir, dir + '/delta2', '');
        if (!other || other.load('network') == null || other.set('network','afawg_case','note','external-change') == null || !other.commit('network'))
            die('Concurrent UCI modification failed\n');
    }
    if (args[0] == 'timeout') return { ok: true, output: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=\t' + time() + '\n' };
    if (args[5] == 'up' && fail_start) return { ok: false };
    if (args[5] == 'status') return { ok: true, output: sprintf('%J', {up:true,l3_device:substr(args[4], length('network.interface.')), 'ipv4-address':[{address:'10.0.0.2',mask:32}]}) };
    return { ok: true, output: '' };
}
let opts = { config_dir: dir, lock_dir: dir + '/apply-lock', runner,
    mark_audit: function() { return {ok:true}; },
    runtime_runner: function(args) { return { ok: true, output: '[]' }; },
    now: function() { return ticks; }, pause: function(n) { ticks += n; } };
let blocked_opts = { ...opts, mark_audit:function() { return {ok:false,error:'IP rule mark conflict'}; } };
expect(!apply.apply(fixture, 'afawg_block', '16908', '1112', 1000, blocked_opts).ok, 'mark conflict accepted');
let blocked_check = uci.cursor(dir, dir + '/delta2', '');
expect(blocked_check.load('network') != null && blocked_check.get('network','afawg_block') == null, 'mark conflict wrote UCI');
let first = apply.apply(fixture, 'afawg_case', '16900', '1100', 1000, opts);
expect(first.ok, 'Apply failed: ' + first.error);
let check = uci.cursor(dir, dir + '/delta2', '');
expect(check.load('network') != null && check.get('network', 'afawg_case', 'proto') == 'amneziawg' &&
    check.get('network', 'wan', 'proto') == 'dhcp', 'Applied network invalid');
// A different managed name tests rollback without modifying the first one.
fail_start = true;
let second = apply.apply(fixture, 'afawg_fail', '16901', '1102', 1000, opts);
expect(!second.ok, 'Simulated activation failure accepted');
let after = uci.cursor(dir, dir + '/delta2', '');
expect(after.load('network') != null && after.get('network', 'afawg_fail') == null &&
    after.get('network', 'afawg_case') != null && after.get('network', 'wan', 'proto') == 'dhcp',
    'Rollback touched unrelated sections or left its own');
fail_start = false;
let wrong = replace(fixture, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=');
let before_calls = length(log);
expect(!apply.cleanup(wrong, 'afawg_case', '16900', '1100', opts).ok && length(log) == before_calls,
    'Cleanup accepted changed key or stopped interface before comparison');
expect(apply.cleanup(fixture, 'afawg_case', '16900', '1100', opts).ok, 'Exact cleanup failed');
let final_cursor = uci.cursor(dir, dir + '/delta2', '');
expect(final_cursor.load('network') != null && final_cursor.get('network', 'afawg_case') == null &&
    final_cursor.get('network', 'afawg_case_peer') == null && final_cursor.get('network', 'wan', 'proto') == 'dhcp',
    'Exact cleanup retained owned sections or changed WAN');
expect(apply.apply(fixture, 'afawg_case', '16900', '1100', 1000, opts).ok, 'Second apply failed');
fail_stop = true;
expect(!apply.cleanup(fixture, 'afawg_case', '16900', '1100', opts).ok, 'Failed stop accepted');
fail_stop = false;
let after_stop = uci.cursor(dir, dir + '/delta2', '');
expect(after_stop.load('network') != null && after_stop.get('network', 'afawg_case') != null, 'Failed stop removed config');
mutate_on_stop = true;
let conflict = apply.cleanup(fixture, 'afawg_case', '16900', '1100', opts);
expect(!conflict.ok && index(sprintf('%J',conflict),'external-change') < 0, 'Concurrent change accepted or exposed');
let after_race = uci.cursor(dir, dir + '/delta2', '');
expect(after_race.load('network') != null && after_race.get('network', 'afawg_case', 'note') == 'external-change' &&
    after_race.get('network', 'wan', 'proto') == 'dhcp', 'Concurrent change or WAN was overwritten');
mutate_on_stop = false;
let stale_session = null;
let batch = apply.with_lock(opts, function(session) {
    stale_session = session;
    expect(session.valid(), 'Active lease is not valid');
    expect(!apply.with_lock(opts, function() { return {ok:true}; }).ok, 'Nested lock allowed');
    expect(!apply.apply(fixture, 'afawg_other', '16904', '1104', 1000, opts).ok, 'Direct apply bypassed held lock');
    expect(session.apply(fixture, 'afawg_lease', '16903', '1106', 1000).ok, 'Session apply failed');
    expect(session.cleanup(fixture, 'afawg_lease', '16903', '1106').ok, 'Session cleanup failed');
    return {ok:true};
});
expect(batch.ok && !stale_session.valid() && !stale_session.apply(fixture, 'afawg_lease', '16903', '1106', 1000).ok, 'Expired session remained valid');
let replaced = apply.with_lock(opts, function(session) {
    expect(session.valid() && fs.rename(opts.lock_dir, dir + '/old-lock') && fs.mkdir(opts.lock_dir, 0700), 'replace test lock');
    expect(!session.valid() && !session.apply(fixture, 'afawg_fake', '16905', '1108', 1000).ok, 'replaced lock accepted');
    return {ok:true};
});
expect(!replaced.ok && fs.stat(opts.lock_dir) != null, 'replacement directory was removed');
fs.rmdir(opts.lock_dir); fs.rmdir(dir + '/old-lock');
let check_count = 0, changed_opts = { ...opts, lock_dir:dir + '/changed-lock' };
changed_opts.runtime_runner = function(args) {
    check_count++;
    if (check_count == 1) {
        expect(fs.rename(changed_opts.lock_dir, dir + '/changed-old') && fs.mkdir(changed_opts.lock_dir, 0700), 'simulate lock replacement');
    }
    return {ok:true,output:'[]'};
};
let changed = apply.with_lock(changed_opts, function(session) {
    return session.apply(fixture, 'afawg_lost', '16906', '1110', 1000);
});
expect(!changed.ok, 'lock replacement before staging accepted');
let check_lost = uci.cursor(dir, dir + '/delta2', '');
expect(check_lost.load('network') != null && check_lost.get('network','afawg_lost') == null, 'UCI committed after lock loss');
fs.rmdir(changed_opts.lock_dir); fs.rmdir(dir + '/changed-old');
print('AWG apply test passed with real isolated UCI and mock netifd\n');
