let fs = require('fs');
let manual = require('subscription.amnezia_manual_source');
let active = require('subscription.amnezia_active');
let generation = require('subscription.amnezia_generation');
function expect(ok, message) { if (!ok) die('FAIL: ' + message + '\n'); }
let root = getenv('ARTAK_AWG_MANUAL_TEST_DIR');
expect(type(root) == 'string' && root != '', 'isolated test directory');
let key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
let conf = '[Interface]\nPrivateKey = ' + key + '\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = ' + key + '\nEndpoint = example.com:443\nAllowedIPs = 0.0.0.0/0\n';
let id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
let source = 'manual_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', candidate = root + '/candidate', good = root + '/good', manifest = root + '/active', generations = root + '/generations';
let generated = manual.new_id(), another = manual.new_id();
expect(type(generated) == 'string' && generated != another && manual.from_id(generated) != null, 'unique random source ID');
expect(manual.from_id('invalid') == null, 'reject invalid source ID');
let entry = { name: 'afawg_1', table: '15001', priority: '16002', secret: key };
let first = manual.stage(candidate, source, id, conf);
expect(first.ok && index(sprintf('%J', first), key) < 0, 'stage and redact');
let fail = manual.publish(candidate, good, manifest, source, id, first.revision, entry, function() { return false; }, generations);
expect(!fail.ok && generation.current_id(generations, source) == null, 'failed verification never publishes');
let published = manual.publish(candidate, good, manifest, source, id, first.revision, entry, function() { return true; }, generations);
expect(published.ok, 'publish');
expect(generation.current_id(generations, source) == published.generation, 'active generation survives read');
let second = manual.stage(candidate, source, id, replace(conf, 'example.com', 'new.example.com'));
expect(second.ok && second.revision != first.revision, 'candidate changed');
expect(!manual.publish(candidate, good, manifest, source, id, first.revision, entry, function() { return true; }, generations).ok, 'reject stale revision');
expect(generation.current_id(generations, source) == published.generation, 'previous last-good generation retained');
let restored = manual.restore(good, generations, source, id, {}, 1000, {
    uci_check: function() { return { ok: true }; }, live_check: function() { return { ok: true }; },
});
expect(type(restored) == 'array' && restored[0].name == 'afawg_1', 'restore verifies last-good revision');
expect(manual.restore(good, generations, source, id, {}, 1000, {
    uci_check: function() { return { ok: true }; }, live_check: function() { return { ok: false }; },
}) == null, 'restore refuses failed live verification');
expect(index(fs.readfile(generations + '/' + source + '-' + published.generation + '.json'), key) < 0, 'generation omits secret');
let legacy = manual.from_id('ffffffffffffffffffffffffffffffff');
let legacy_stage = manual.stage(candidate, legacy.source, legacy.identity, conf);
expect(legacy_stage.ok && require('subscription.amnezia_store').promote(candidate, good, legacy.source, legacy.identity, legacy_stage.revision), 'prepare legacy');
expect(active.save(manifest, legacy.source, legacy.identity, legacy_stage.revision,
 [{index:0,name:'afawg_2',table:'15002',priority:'16004'}], function() { return true; }), 'legacy manifest');
let migrate_opts = { current:function() { return true; }, uci_check:function() { return {ok:true}; }, live_check:function() { return {ok:true}; } };
expect(manual.migrate(good, manifest, generations, legacy.source, legacy.identity, {}, 1000, migrate_opts), 'migrate validated legacy');
expect(generation.current_id(generations, legacy.source) != null, 'migration creates current pointer');
expect(!manual.migrate(good, manifest, generations, legacy.source, legacy.identity, {}, 1000, migrate_opts), 'migration never overwrites current');
let activation = require('subscription.amnezia_manual_activate');
let cleanup_count = 0;
let opts = {
 current: function() { return true; }, cursor: {},
 choose: function() { return { ok: true, name: 'afawg_3', table: '15003', priority: '16006' }; },
 with_lock: function(o, fn) { return fn({ apply: function() { return { ok: true }; }, cleanup: function() { cleanup_count++; return {ok:true}; } }); },
 verify_cursor: function() { return { load: function() { return true; } }; },
 uci_check: function() { return {ok:true}; }, live_check: function() { return {ok:true}; },
};
let dirs = { candidate, last_good: good, active: manifest, generation: generations };
let other = manual.from_id('cccccccccccccccccccccccccccccccc');
let failed = manual.from_id('dddddddddddddddddddddddddddddddd');
let changed = manual.from_id('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee');
let applied = activation.activate(conf, other.source, other.identity, dirs, opts);
expect(applied.ok && applied.name == 'afawg_3', 'activate under backend lease');
opts.live_check = function() { return {ok:false}; };
applied = activation.activate(conf, failed.source, failed.identity, dirs, opts);
expect(!applied.ok && !applied.cleanup_required && cleanup_count == 1, 'failed verification cleans only own interface');
expect(generation.current_id(generations, failed.source) == null, 'failed activation not published');
opts.current = function() { return false; };
applied = activation.activate(conf, changed.source, changed.identity, dirs, opts);
expect(!applied.ok && cleanup_count == 1 && generation.current_id(generations, changed.source) == null, 'changed rule cannot activate');
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
