let fs = require('fs');
let manual = require('subscription.amnezia_manual_source');
let active = require('subscription.amnezia_active');
function expect(ok, message) { if (!ok) die('FAIL: ' + message + '\n'); }
let root = getenv('ARTAK_AWG_MANUAL_TEST_DIR');
expect(type(root) == 'string' && root != '', 'isolated test directory');
let key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
let conf = '[Interface]\nPrivateKey = ' + key + '\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = ' + key + '\nEndpoint = example.com:443\nAllowedIPs = 0.0.0.0/0\n';
let id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
let source = 'manual_example', candidate = root + '/candidate', good = root + '/good', manifest = root + '/active';
let entry = { name: 'afawg_1', table: '15001', priority: '16002', secret: key };
let first = manual.stage(candidate, source, id, conf);
expect(first.ok && index(sprintf('%J', first), key) < 0, 'stage and redact');
let fail = manual.publish(candidate, good, manifest, source, id, first.revision, entry, function() { return false; });
expect(!fail.ok && active.peek(manifest, source, id) == null, 'failed verification never publishes');
expect(manual.publish(candidate, good, manifest, source, id, first.revision, entry, function() { return true; }).ok, 'publish');
expect(active.peek(manifest, source, id) == first.revision, 'active revision survives read');
let second = manual.stage(candidate, source, id, replace(conf, 'example.com', 'new.example.com'));
expect(second.ok && second.revision != first.revision, 'candidate changed');
expect(!manual.publish(candidate, good, manifest, source, id, first.revision, entry, function() { return true; }).ok, 'reject stale revision');
expect(active.peek(manifest, source, id) == first.revision, 'previous last-good manifest retained');
let restored = manual.restore(good, manifest, source, id, {}, 1000, {
    uci_check: function() { return { ok: true }; }, live_check: function() { return { ok: true }; },
});
expect(type(restored) == 'array' && restored[0].name == 'afawg_1', 'restore verifies last-good revision');
expect(manual.restore(good, manifest, source, id, {}, 1000, {
    uci_check: function() { return { ok: true }; }, live_check: function() { return { ok: false }; },
}) == null, 'restore refuses failed live verification');
expect(index(fs.readfile(manifest + '/' + source + '.json'), key) < 0, 'manifest omits secret');
print('Manual AWG source persistence checks passed\n');
