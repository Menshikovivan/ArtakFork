// Invoked with a fresh private test directory by amnezia_store.sh.
let fs = require('fs');
let store = require('subscription.amnezia_store');
let subscription = require('subscription.amnezia_subscription');
let main_parser = require('subscription.parser');
function expect(v, message) { if (!v) die('FAIL: ' + message + '\n'); }
let dir = ARGV[0];
let id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let other = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
let key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
let good = '[Interface]\nPrivateKey = ' + key + '\nAddress = 10.0.0.2/32\n' +
    'Jc = 4\nJmin = 40\nJmax = 70\n[Peer]\nPublicKey = ' + key + '\n' +
    'Endpoint = awg.example.invalid:443\nAllowedIPs = 0.0.0.0/0\n';
let bad = replace(good, '[Peer]', 'PostUp = echo BAD\n[Peer]');
let vpn = 'vpn://' + b64enc(good);
let badvpn = 'vpn://' + b64enc(bad);
let mixed = b64enc('vless://test.invalid\n' + vpn + '\n');
expect(subscription.validated(mixed).ok, 'valid mixed feed rejected');
expect(!subscription.validated(vpn + '\n' + badvpn).ok, 'unsafe mixed feed accepted');
expect(fs.writefile(dir + '/synthetic-feed', mixed) != null, 'test feed write failed');
expect(main_parser.parse_amnezia_subscription_file(dir + '/synthetic-feed').ok, 'main parser entry failed');
fs.unlink(dir + '/synthetic-feed');
expect(store.save(dir, 'rule_1', id, mixed), 'valid store write failed');
let old = fs.readfile(dir + '/rule_1.awg.json');
expect(type(old) == 'string' && length(old) > 0, 'record missing');
expect(length(store.load(dir, 'rule_1', id)) == 1, 'record did not load');
expect(store.load(dir, 'rule_1', other) == null, 'mismatched source identity loaded');
expect(!store.save(dir, 'rule_1', id, vpn + '\n' + badvpn), 'unsafe feed saved');
expect(!store.save(dir, 'rule_1', id, 'vpn://malformed!'), 'malformed feed saved');
expect(!store.save(dir, '../outside', id, mixed), 'invalid path accepted');
expect(fs.readfile(dir + '/rule_1.awg.json') == old, 'failure overwrote prior record');
expect(fs.writefile(dir + '/corrupt.awg.json', '{bad') != null, 'failed to create fixture');
expect(store.load(dir, 'corrupt', id) == null, 'corrupt record loaded');
print('AWG private storage, source isolation and last-known-good checks passed\n');
