// No actual credentials: exercise the same extraction, validation and netifd
// staging-plan APIs that a future subscription integration must call.
let subscription = require('subscription.amnezia_subscription');
let conf = require('subscription.amnezia_conf');
let netifd = require('subscription.amnezia_netifd');
function expect(ok, message) { if (!ok) die('FAIL: ' + message + '\n'); }
function uri(value) {
    return 'vpn://' + replace(replace(replace(b64enc(value), /\+/g, '-'), /\//g, '_'), /=+$/g, '');
}

let key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
let serverkey = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=';
let base = '[Interface]\nPrivateKey = ' + key + '\nAddress = 10.8.1.2/32\n' +
    'Jc = 4\nJmin = 40\nJmax = 70\nS1 = 72\nS2 = 56\nS3 = 32\nS4 = 16\n' +
    'H1 = 100-110\nH2 = 200-210\nH3 = 300-310\nH4 = 400-410\nI1 = <r 148>\n';
let peer = '[Peer]\nPublicKey = ' + serverkey + '\nAllowedIPs = 0.0.0.0/0, ::/0\n' +
    'Endpoint = awg.example.invalid:10444\nPersistentKeepalive = 25\n';
let awg2 = base + peer;
let awg31 = base + 'HeaderProtectionKey = ' + key + '\nContentPaddingAddition = 17-49\n' +
    'RekeyAfterTime = 300-500\nRekeyTimeout = 10-15\nRejectAfterTime = 600-900\n' +
    'KeepaliveTimeout = 20-25\nMaxHandshakeAttempts = 10-15\n' +
    'RandomTrailers = off\nDisableCookies = on\n' + peer;
let injected = base + 'PostUp = touch /tmp/should-never-exist\n' + peer;
let bad = base + 'SomeUnknownField = unsafe\n' + peer;
let mixed = 'vless://not-a-real-link\n' + uri(awg2) + '\n' + uri(awg31) + '\n' +
    uri(injected) + '\n' + uri(bad) + '\nvpn://invalid!\n';
let extracted = subscription.extract(b64enc(mixed));
expect(length(extracted.configs) == 4 && extracted.invalid == 1, 'mixed raw subscription extraction');
let p2 = conf.parse_conf(extracted.configs[0]);
let p31 = conf.parse_conf(extracted.configs[1]);
expect(p2.ok && p31.ok, 'valid 2.0 and 3.1 profiles must parse');
let n2 = netifd.prepare(p2, 'afawg_a1');
let n31 = netifd.prepare(p31, 'afawg_a2');
expect(n2.ok && n31.ok, 'valid profiles must prepare');
expect(n2.iface.awg_h1 == '100-110' && n2.iface.awg_i1 == '<r 148>', '2.0 parameters lost');
expect(n31.iface.awg_header_protection_key == key && n31.iface.awg_content_padding_addition == '17-49' &&
    n31.iface.awg_disable_cookies == '1' && n31.iface.awg_random_trailers == '0', '3.1 parameters lost');
expect(n31.peer.endpoint_host == 'awg.example.invalid' && n31.peer.endpoint_port == '10444' &&
    n31.iface.defaultroute == '0' && n31.iface.peerdns == '0' && n31.peer.route_allowed_ips == '0', 'endpoint or routing policy changed');
for (let i = 2; i < 4; i++) {
    let rejected = conf.parse_conf(extracted.configs[i]);
    expect(!rejected.ok && !netifd.prepare(rejected, 'afawg_a3').ok, 'unsafe configuration reached netifd');
}
print('3x-ui subscription extraction, AWG 2.0/3.1 parsing, netifd plan and hook rejection checks passed\n');
