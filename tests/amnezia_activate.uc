let activation = require('subscription.amnezia_activate');
function expect(v, m) { if (!v) die(m + '\n'); }
expect(type(activation.ready) == 'function' && type(activation.run) == 'function', 'Activation module API missing ready or run');
let log = [], ticks = 0, mode = '';
function run(args) {
    push(log, args);
    let method = args[5];
    if (mode == 'reload' && method == 'reload') return { ok: false };
    if (mode == 'up' && method == 'up') return { ok: false };
    if (method == 'status') return { ok: true, output: sprintf('%J', {
        up: mode != 'timeout', l3_device: mode == 'wrong_device' ? 'wan' : 'afawg_test',
        'ipv4-address': [{ address: mode == 'wrong_addr' ? '10.0.0.3' : '10.0.0.2', mask: 32 }]
    }) };
    return { ok: true, output: '' };
}
function now() { return ticks; }
function pause(n) { ticks += n; }
expect(!activation.start('wan', ['10.0.0.2/32'], 1000, run, pause, now).ok && length(log) == 0, 'Unsafe name accepted');
expect(!activation.start('afawg_test', ['10.0.0.2;cmd/32'], 1000, run, pause, now).ok && length(log) == 0, 'Unsafe address accepted');
mode = ''; expect(activation.start('afawg_test', ['10.0.0.2/32'], 1000, run, pause, now).ok, 'Expected ready interface');
expect(log[0][4] == 'network' && log[0][5] == 'reload' && log[1][4] == 'network.interface.afawg_test' && log[1][5] == 'up', 'Unexpected ubus arguments');
log = []; ticks = 0; mode = 'wrong_addr';
expect(!activation.start('afawg_test', ['10.0.0.2/32'], 1000, run, pause, now).ok && ticks == 1000, 'Wrong address accepted');
log = []; ticks = 0; mode = 'wrong_device';
expect(!activation.start('afawg_test', ['10.0.0.2/32'], 1000, run, pause, now).ok, 'Wrong device accepted');
log = []; ticks = 0; mode = 'reload';
expect(!activation.start('afawg_test', ['10.0.0.2/32'], 1000, run, pause, now).ok && length(log) == 1, 'Reload failure ignored');
log = []; mode = ''; expect(activation.stop('afawg_test', run).ok && log[0][5] == 'down', 'Stop failed');
print('AmneziaWG activation tests passed\n');
