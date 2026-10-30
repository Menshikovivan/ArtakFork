let netifd = require('subscription.amnezia_netifd');
let parser = require('subscription.amnezia_conf');
function expect(value, message) { if (!value) die(message + '\n'); }
let config = { ok: true,
    interface: { private_key: 'test-private-key', addresses: ['10.0.0.2/32'], dns: ['1.1.1.1'],
        awg_h1: '100-200', awg_disable_cookies: '1' },
    peers: [{ public_key: 'test-public-key', allowed_ips: ['0.0.0.0/0'],
        endpoint_host: 'vpn.example', endpoint_port: '8443', route_allowed_ips: '1' }] };
let prepared = netifd.prepare(config, 'afawg_a1');
let fixture = '[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' +
    'Address = 10.0.0.2/32\nJc = 4\nH1 = 100-200\nDisableCookies = on\n' +
    '[Peer]\nPublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=\n' +
    'AllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example:8443\n';
let from_conf = netifd.prepare(parser.parse_conf(fixture), 'afawg_conf');
expect(from_conf.ok && from_conf.iface.awg_disable_cookies == '1' && from_conf.peer.endpoint_port == '8443',
    'Parser and netifd adapter do not agree');
expect(prepared.ok, 'Expected valid prepared interface');
expect(prepared.iface.proto == 'amneziawg' && prepared.iface.defaultroute == '0' &&
    prepared.iface.peerdns == '0' && prepared.iface.dns == null, 'Default routing or DNS changed');
expect(prepared.peer.route_allowed_ips == '0' && prepared.peer_type == 'amneziawg_afawg_a1',
    'Unexpected peer routing or section type');
expect(!netifd.prepare(config, 'wan').ok && !netifd.prepare(config, 'afawg_123456789').ok,
    'Unsafe interface name accepted');
let sections = {}, fail = '', return_null = '';
let cursor = {
    load: function(pkg) { return true; },
    get: function(pkg, section) { return sections[section]; },
    set: function(pkg, section, opt, value) {
        if (opt == fail) die('forced failure');
        if (opt == return_null) return null;
        if (value == null) sections[section] = { '.type': opt };
        else sections[section][opt] = value;
        return true;
    },
    delete: function(pkg, section) { delete sections[section]; }
};
expect(netifd.stage_new(cursor, config, 'afawg_a1').ok, 'Staging failed');
expect(sections.afawg_a1.proto == 'amneziawg' && sections.afawg_a1_peer.route_allowed_ips == '0',
    'Wrong UCI values');
expect(!netifd.stage_new(cursor, config, 'afawg_a1').ok, 'Overwrote existing interface');
fail = 'public_key';
expect(!netifd.stage_new(cursor, config, 'afawg_b2').ok, 'Simulated error accepted');
expect(sections.afawg_b2 == null && sections.afawg_b2_peer == null && sections.afawg_a1 != null,
    'Failed staging did not roll back only new sections');
fail = ''; return_null = 'public_key';
expect(!netifd.stage_new(cursor, config, 'afawg_c3').ok, 'Null UCI result accepted');
expect(sections.afawg_c3 == null && sections.afawg_c3_peer == null, 'Null result not rolled back');
print('AmneziaWG netifd staging tests passed\n');
