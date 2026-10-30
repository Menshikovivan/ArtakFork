let uci = require('uci');
let apply = require('subscription.amnezia_apply');
function expect(v, m) { if (!v) die(m + '\n'); }
let dir = getenv('ARTAK_TEST_UCI_DIR');
if (type(dir) != 'string' || !match(dir, /^\/tmp\/artak-uci-test\.[A-Za-z0-9]+$/)) die('Unsafe test directory\n');
let fixture = '[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\nAddress = 10.0.0.2/32\n' +
    '[Peer]\nPublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=\nAllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example:8443\n';
let log = [], ticks = 0, fail_start = false;
function runner(args) {
    push(log, args);
    if (args[0] == 'timeout') return { ok: true, output: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=\t' + time() + '\n' };
    if (args[5] == 'up' && fail_start) return { ok: false };
    if (args[5] == 'status') return { ok: true, output: '{"up":true,"l3_device":"afawg_case","ipv4-address":[{"address":"10.0.0.2","mask":32}]}' };
    return { ok: true, output: '' };
}
let opts = { config_dir: dir, lock_dir: dir + '/apply-lock', runner,
    runtime_runner: function(args) { return { ok: true, output: '[]' }; },
    now: function() { return ticks; }, pause: function(n) { ticks += n; } };
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
print('AWG apply test passed with real isolated UCI and mock netifd\n');
