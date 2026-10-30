// Invoked with a fresh private test directory by amnezia_store.sh.
let fs = require('fs');
let store = require('subscription.amnezia_store');
let subscription = require('subscription.amnezia_subscription');
let main_parser = require('subscription.parser');
let candidates = require('subscription.amnezia_candidates');
let candidate_apply = require('subscription.amnezia_candidate_apply');
let active = require('subscription.amnezia_active');
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
let allocation = [{ name: 'afawg_a1', table: '10001', priority: '1000' }];
let plan = candidates.prepare(dir, 'rule_1', id, allocation);
expect(plan.ok && length(plan.plans) == 1, 'candidate did not prepare for AWG runtime');
expect(plan.plans[0].network.iface.private_key == key && plan.plans[0].network.peer.route_allowed_ips == '0', 'candidate lost key or route policy');
expect(plan.plans[0].routing.entries[0].options.table == '10001', 'candidate lost table');
expect(!candidates.prepare(dir, 'rule_1', other, allocation).ok, 'wrong identity planned');
expect(!candidates.prepare(dir, 'rule_1', id, []).ok, 'missing allocation accepted');
expect(store.save(dir, 'rule_2', id, vpn + '\n' + vpn), 'two-profile candidate write failed');
let old_two = fs.readfile(dir + '/rule_2.awg.json');
let called = 0;
let fake_apply = function(text, name, table, priority, timeout, options) {
    called++;
    expect(text == good && name == 'afawg_a1' && table == '10001' && priority == '1000', 'apply arguments changed');
    return { ok: true };
};
let applied = candidate_apply.apply_one(dir, 'rule_2', id, 1, allocation[0], 1000, { apply_driver: fake_apply });
expect(applied.ok && called == 1, 'selected candidate not passed to runtime');
expect(!candidate_apply.apply_one(dir, 'rule_2', other, 0, allocation[0], 1000, { apply_driver: fake_apply }).ok && called == 1, 'wrong source reached runtime');
expect(!candidate_apply.apply_one(dir, 'rule_2', id, 7, allocation[0], 1000, { apply_driver: fake_apply }).ok && called == 1, 'invalid index reached runtime');
let failing = function() { return { ok: false, error: key }; };
let failure = candidate_apply.apply_one(dir, 'rule_2', id, 0, allocation[0], 1000, { apply_driver: failing });
expect(!failure.ok && index(sprintf('%J', failure), key) < 0, 'runtime error leaked secret');
expect(fs.readfile(dir + '/rule_2.awg.json') == old_two, 'failed runtime touched selected candidate');
let active_dir = dir + '/active';
expect(fs.mkdir(active_dir), 'could not create active fixture directory');
let revision = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
let manifest = { dir: active_dir, revision: revision, verify: function(e) { return e.name == 'afawg_a1'; } };
let applied_mapped = candidate_apply.apply_one_and_record(dir, 'rule_2', id, 1, allocation[0], 1000, { apply_driver: fake_apply }, manifest);
expect(applied_mapped.ok && length(active.restore(active_dir, 'rule_2', id, revision, manifest.verify)) == 1, 'active mapping was not written after verified apply');
let previous_mapping = fs.readfile(active_dir + '/rule_2.json');
manifest.verify = function(e) { return false; };
let failed_map = candidate_apply.apply_one_and_record(dir, 'rule_2', id, 0, allocation[0], 1000, { apply_driver: fake_apply }, manifest);
expect(!failed_map.ok && failed_map.cleanup_required && fs.readfile(active_dir + '/rule_2.json') == previous_mapping, 'failed mapping was accepted or overwrote previous');
let two = [
    { name: 'afawg_a1', table: '10001', priority: '1000' },
    { name: 'afawg_a2', table: '10002', priority: '1002' }
];
expect(candidates.prepare(dir, 'rule_2', id, two).ok, 'two distinct allocations rejected');
two[1].priority = '1001';
expect(!candidates.prepare(dir, 'rule_2', id, two).ok, 'overlapping priorities accepted');
two[1].priority = '1002'; two[1].table = '10001';
expect(!candidates.prepare(dir, 'rule_2', id, two).ok, 'duplicate table accepted');
two[1].table = '10002'; two[1].name = 'afawg_a1';
let duplicate_name = candidates.prepare(dir, 'rule_2', id, two);
expect(!duplicate_name.ok, 'duplicate interface accepted');
expect(index(sprintf('%J', duplicate_name), key) < 0, 'failure returned private key');
two[1].name = 'wan';
expect(!candidates.prepare(dir, 'rule_2', id, two).ok, 'unmanaged interface name accepted');
expect(!store.save(dir, 'rule_1', id, vpn + '\n' + badvpn), 'unsafe feed saved');
expect(!store.save(dir, 'rule_1', id, 'vpn://malformed!'), 'malformed feed saved');
expect(!store.save(dir, '../outside', id, mixed), 'invalid path accepted');
expect(fs.readfile(dir + '/rule_1.awg.json') == old, 'failure overwrote prior record');
expect(fs.writefile(dir + '/corrupt.awg.json', '{bad') != null, 'failed to create fixture');
expect(store.load(dir, 'corrupt', id) == null, 'corrupt record loaded');
print('AWG private storage, source isolation and last-known-good checks passed\n');
