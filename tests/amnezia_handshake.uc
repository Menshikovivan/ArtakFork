let handshake = require('subscription.amnezia_handshake');
function expect(v, m) { if (!v) die(m + '\n'); }
let peer = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=', ticks = 0, mode = '', calls = [];
function now() { return ticks; }
function pause(n) { ticks += n; }
function wall() { return 10000; }
function run(args) {
    push(calls, args);
    if (mode == 'error') return { ok: false };
    let stamp = mode == 'zero' ? '0' : mode == 'old' ? '9800' : mode == 'future' ? '10001' : '9990';
    return { ok: true, output: (mode == 'other' ? 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' : peer) + '\t' + stamp + '\n' };
}
expect(handshake.verify('afawg_a', peer, 1000, run, pause, now, wall).ok, 'Recent handshake rejected');
expect(calls[0][0] == 'timeout' && calls[0][2] == 'awg' && calls[0][4] == 'afawg_a', 'Unexpected command');
for (let test in ['zero', 'old', 'future', 'other', 'error']) {
    mode = test; ticks = 0;
    let result = handshake.verify('afawg_a', peer, 1000, run, pause, now, wall);
    expect(!result.ok && index(sprintf('%J', result), peer) < 0, 'Invalid handshake accepted or peer leaked: ' + test);
}
expect(!handshake.verify('wan', peer, 1000, run, pause, now, wall).ok, 'Unsafe device accepted');
print('AmneziaWG handshake tests passed\n');
