// Invoked with a fresh private test directory by amnezia_store.sh.
let fs = require('fs');
let store = require('subscription.amnezia_store');
let subscription = require('subscription.amnezia_subscription');
let main_parser = require('subscription.parser');
let candidates = require('subscription.amnezia_candidates');
let candidate_apply = require('subscription.amnezia_candidate_apply');
let active = require('subscription.amnezia_active');
let restore = require('subscription.amnezia_restore');
let source_identity = require('subscription.amnezia_identity');
let runtime_subscription = require('singbox.subscription');
let snapshot = require('subscription.amnezia_snapshot');
function expect(v, message) { if (!v) die('FAIL: ' + message + '\n'); }
let dir = ARGV[0];
let identity_a = source_identity.calculate(dir, 'test', 'https://example.invalid/sub', 'agent', 'device');
expect(type(identity_a) == 'string' && length(identity_a) == 64, 'source identity not computed');
expect(identity_a == source_identity.calculate(dir, 'test', 'https://example.invalid/sub', 'agent', 'device'), 'identity not deterministic');
expect(identity_a != source_identity.calculate(dir, 'test', 'https://example.invalid/other', 'agent', 'device'), 'source URL not bound');
expect(source_identity.calculate(dir, '../bad', 'a', 'b', 'c') == null, 'unsafe source accepted');
let source_dir = ARGV[1];
fs.writefile(source_dir + '/fixture.url', 'https://example.invalid/sub\n');
fs.writefile(source_dir + '/fixture.user_agent', 'agent\n');
fs.writefile(source_dir + '/fixture.hwid', 'device\n');
expect(runtime_subscription.awg_source_identity('fixture', 'https://example.invalid/sub', 'agent', 'device', dir) == identity_a, 'source cache identity differs from downloader');
expect(runtime_subscription.awg_source_identity('fixture', 'https://example.invalid/other', 'agent', 'device', dir) == null, 'stale source cache accepted');
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
let revision = store.revision(dir, 'rule_2', id);
expect(type(revision) == 'string' && length(revision) == 64, 'candidate revision missing');
expect(store.revision(dir, 'rule_2', other) == null, 'wrong identity hashed');
let snapshot_dir = dir + '/snapshot';
expect(fs.mkdir(snapshot_dir), 'snapshot directory creation failed');
let snapshot_entry = { index: 1, name: 'afawg_a1', table: '10001', priority: '1000',
    mark: 0x18000000 | 10001, source: 'rule_2', identity: id, revision: revision, private_key: key };
let saved_snapshot = snapshot.save(snapshot_dir, [snapshot_entry]);
expect(saved_snapshot != null && snapshot.load(snapshot_dir).revision == saved_snapshot.revision, 'snapshot did not round trip');
expect(index(fs.readfile(snapshot_dir + '/snapshot.json'), key) < 0, 'snapshot leaked private key');
expect(snapshot.save(snapshot_dir, [snapshot_entry, snapshot_entry]) == null, 'duplicate snapshot entry accepted');
expect(snapshot.load(snapshot_dir).revision == saved_snapshot.revision, 'invalid snapshot overwrote previous');
let build_opts = {
    revision: function() { return revision; },
    peek: function() { return revision; },
    restore: function() { return [{ index: 1, name: 'afawg_a1', table: '10001', priority: '1000' }]; }
};
let built = snapshot.build(snapshot_dir, dir, active_dir, [{ source: 'rule_2', identity: id }], null, 1000, [], build_opts);
expect(built != null && built.entries[0].mark == snapshot_entry.mark, 'verified entries not assembled into snapshot');
expect(snapshot.build(snapshot_dir, dir, active_dir, [{ source: 'rule_2', identity: id }], null, 1000, [snapshot_entry.mark], build_opts) == null, 'occupied mark accepted');
let manifest = { dir: active_dir, revision: revision, verify: function(e) { return e.name == 'afawg_a1'; } };
let stale_manifest = { dir: active_dir, revision: other, verify: manifest.verify };
expect(!candidate_apply.apply_one_and_record(dir, 'rule_2', id, 1, allocation[0], 1000, { apply_driver: fake_apply }, stale_manifest).ok && called == 1, 'stale revision reached runtime');
let mutate_apply = function() { store.save(dir, 'rule_2', id, vpn); return { ok: true }; };
let failed_cleanup = function() { return { ok: false }; };
let changed_during_apply = candidate_apply.apply_one_and_record(dir, 'rule_2', id, 1, allocation[0], 1000, { apply_driver: mutate_apply, cleanup_driver: failed_cleanup }, manifest);
expect(!changed_during_apply.ok && changed_during_apply.cleanup_required, 'changed candidate published after apply');
expect(store.save(dir, 'rule_2', id, vpn + '\n' + vpn), 'candidate reset after changed apply failed');
let applied_mapped = candidate_apply.apply_one_and_record(dir, 'rule_2', id, 1, allocation[0], 1000, { apply_driver: fake_apply }, manifest);
expect(applied_mapped.ok && length(active.restore(active_dir, 'rule_2', id, revision, manifest.verify)) == 1, 'active mapping was not written after verified apply');
let last_good = dir + '/last-good';
expect(store.promote(dir, last_good, 'rule_2', id, revision), 'candidate promotion failed');
let checks = { uci_check: function() { return { ok: true }; }, live_check: function() { return { ok: true }; } };
expect(length(restore.restore(last_good, active_dir, 'rule_2', id, null, 1000, checks)) == 1, 'candidate-backed restore failed');
checks.live_check = function() { return { ok: false }; };
expect(restore.restore(last_good, active_dir, 'rule_2', id, null, 1000, checks) == null, 'down interface restored');
checks.live_check = function() { return { ok: true }; };
checks.uci_check = function() { return { ok: false }; };
expect(restore.restore(last_good, active_dir, 'rule_2', id, null, 1000, checks) == null, 'changed UCI restored');
checks.uci_check = function() { return { ok: true }; };
expect(store.save(dir, 'rule_2', id, vpn), 'candidate replacement failed');
expect(length(restore.restore(last_good, active_dir, 'rule_2', id, null, 1000, checks)) == 1, 'replacement candidate destroyed last-good');
expect(store.save(dir, 'rule_2', id, vpn + '\n' + vpn), 'candidate fixture reset failed');
let good_path = last_good + '/' + revision + '/rule_2.awg.json';
let saved_good = fs.readfile(good_path);
expect(fs.writefile(good_path, saved_good + ' ') != null, 'last-good tamper fixture failed');
expect(restore.restore(last_good, active_dir, 'rule_2', id, null, 1000, checks) == null, 'modified last-good restored');
expect(fs.writefile(good_path, saved_good) != null, 'last-good fixture restore failed');
let previous_mapping = fs.readfile(active_dir + '/rule_2.json');
manifest.verify = function(e) { return false; };
let failed_map = candidate_apply.apply_one_and_record(dir, 'rule_2', id, 0, allocation[0], 1000, { apply_driver: fake_apply, cleanup_driver: failed_cleanup }, manifest);
expect(!failed_map.ok && failed_map.cleanup_required && fs.readfile(active_dir + '/rule_2.json') == previous_mapping, 'failed mapping was accepted or overwrote previous');
let cleaned = false;
let successful_cleanup = function(text, name) { cleaned = text == good && name == 'afawg_a1'; return { ok: true }; };
let failed_map_cleaned = candidate_apply.apply_one_and_record(dir, 'rule_2', id, 0, allocation[0], 1000, { apply_driver: fake_apply, cleanup_driver: successful_cleanup }, manifest);
expect(!failed_map_cleaned.ok && !failed_map_cleaned.cleanup_required && cleaned, 'failed manifest was not rolled back');
let activate_opts = { apply_driver: fake_apply, cleanup_driver: successful_cleanup,
    last_good_dir: dir + '/last-good',
    cursor: { load: function() { return true; } },
    uci_check: function() { return { ok: true }; }, live_check: function() { return { ok: true }; } };
let activate_dir = dir + '/activate';
expect(fs.mkdir(activate_dir), 'activate fixture directory creation failed');
let activated = candidate_apply.activate(dir, activate_dir, 'rule_2', id, 0, allocation[0], 1000, activate_opts);
expect(activated.ok, 'verified candidate was not activated and recorded');
expect(!candidate_apply.activate(dir, activate_dir, 'rule_2', id, 0, allocation[0], 1000, activate_opts).ok, 'existing manifest overwritten');
fs.unlink(activate_dir + '/rule_2.json');
activate_opts.live_check = function() { return { ok: false }; };
cleaned = false;
let not_ready = candidate_apply.activate(dir, activate_dir, 'rule_2', id, 0, allocation[0], 1000, activate_opts);
expect(!not_ready.ok && !not_ready.cleanup_required && cleaned, 'unverified candidate was not rolled back');
activate_opts.live_check = function() { return { ok: true }; };
activate_opts.choose = function() { return { ok: true, name: 'afawg_a1', table: '10001', priority: '1000' }; };
expect(candidate_apply.allocate_and_activate(dir, activate_dir, 'rule_2', id, 0, 1000, activate_opts).ok, 'allocated candidate was not activated');
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
