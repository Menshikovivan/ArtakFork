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
let generated = manual.new_id(), another = manual.new_id();
expect(type(generated) == 'string' && generated != another && manual.from_id(generated) != null, 'unique random source ID');
expect(manual.from_id('invalid') == null, 'reject invalid source ID');
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
let activation = require('subscription.amnezia_manual_activate');
let cleanup_count = 0;
let opts = {
 current: function() { return true; }, cursor: {},
 choose: function() { return { ok: true, name: 'afawg_3', table: '15003', priority: '16006' }; },
 with_lock: function(o, fn) { return fn({ apply: function() { return { ok: true }; }, cleanup: function() { cleanup_count++; return {ok:true}; } }); },
 verify_cursor: function() { return { load: function() { return true; } }; },
 uci_check: function() { return {ok:true}; }, live_check: function() { return {ok:true}; },
};
let dirs = { candidate, last_good: good, active: manifest };
let applied = activation.activate(conf, 'manual_other', id, dirs, opts);
expect(applied.ok && applied.name == 'afawg_3', 'activate under backend lease');
opts.live_check = function() { return {ok:false}; };
applied = activation.activate(conf, 'manual_failed', id, dirs, opts);
expect(!applied.ok && !applied.cleanup_required && cleanup_count == 1, 'failed verification cleans only own interface');
expect(active.peek(manifest, 'manual_failed', id) == null, 'failed activation not published');
opts.current = function() { return false; };
applied = activation.activate(conf, 'manual_changed', id, dirs, opts);
expect(!applied.ok && cleanup_count == 1 && active.peek(manifest, 'manual_changed', id) == null, 'changed rule cannot activate');
let binding = require('subscription.amnezia_manual_binding');
let rule = { '.type':'rule', action:'connection', name:'test' }, commits = 0;
let rules = {
 load: function() { return true; }, get_all: function() { return rule; },
 set: function(pkg, section, option, value) { rule[option] = value; return true; },
 commit: function() { commits++; return true; },
};
let bound = binding.bind(rules, 'rule1', function() { return '1234567890abcdef1234567890abcdef'; });
expect(bound.ok && commits == 1 && binding.current(rules, 'rule1', bound), 'bind unique source ID');
rule.name = 'changed';
expect(!binding.current(rules, 'rule1', bound), 'reject changed section snapshot');
print('Manual AWG source persistence checks passed\n');
