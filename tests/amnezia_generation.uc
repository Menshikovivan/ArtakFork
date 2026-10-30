let fs = require('fs');
let store = require('subscription.amnezia_store');
let ident = require('subscription.amnezia_identity');
let generation = require('subscription.amnezia_generation');
let journal = require('subscription.amnezia_swap_journal');
let swap = require('subscription.amnezia_swap');
let orchestrator = require('subscription.amnezia_orchestrator');
let generation_restore = require('subscription.amnezia_generation_restore');
let legacy_store = require('subscription.amnezia_legacy_store');
function expect(v, msg) { if (!v) die('FAIL: ' + msg + '\n'); }
let base = ARGV[0], candidates = base + '/candidate', good = base + '/good', gen = base + '/generation', jdir = base + '/journal';
expect(fs.mkdir(candidates) && fs.mkdir(good) && fs.mkdir(gen) && fs.mkdir(jdir), 'fixture directories');
let key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
let config = '[Interface]\nPrivateKey = ' + key + '\nAddress = 10.0.0.2/32\n' +
    '[Peer]\nPublicKey = ' + key + '\nEndpoint = awg.example.invalid:443\nAllowedIPs = 0.0.0.0/0\n';
let id = ident.calculate(candidates, 'source', 'https://example.invalid/sub', 'agent', 'device');
expect(store.save(candidates, 'source', id, 'vpn://' + b64enc(config)), 'first candidate');
let first = store.revision(candidates, 'source', id);
expect(store.promote(candidates, good, 'source', id, first), 'first promotion');
let record = {version:1, source:'source', identity:id, revision:first, url:'https://example.invalid/sub', user_agent:'agent', hwid:'device',
    entries:[{index:0,name:'afawg_1',table:'15001',priority:'16002',private_key:key}]};
let first_id = generation.stage(gen, good, record, function() { return true; });
expect(first_id != null && generation.switch_to(gen, 'source', null, first_id), 'first generation publication');
record.mode = 'mixed';
expect(generation.stage(gen, good, record, function() { return true; }) == null, 'mixed generation without legacy hash accepted');
let legacy_text = '{"outbounds":[{"type":"direct","tag":"example"}]}';
expect(fs.writefile(base + '/legacy.json', legacy_text) != null, 'legacy fixture');
record.legacy_revision = generation.hash_file(base + '/legacy.json');
let legacy_dir = base + '/legacy-good';
expect(legacy_store.put(base + '/legacy.json', legacy_dir) == record.legacy_revision &&
    legacy_store.path(legacy_dir, record.legacy_revision) != null, 'immutable legacy stage');
expect(fs.writefile(base + '/legacy.json', '{"outbounds":[{"type":"direct"}]}') != null &&
    legacy_store.path(legacy_dir, record.legacy_revision) != null, 'staged legacy changed with mutable source');
let immutable = legacy_store.path(legacy_dir, record.legacy_revision);
expect(fs.writefile(immutable, '{}') != null && legacy_store.path(legacy_dir, record.legacy_revision) == null,
    'tampered immutable legacy accepted');
expect(fs.writefile(immutable, legacy_text) != null, 'restore immutable fixture');
let mixed_id = generation.stage(gen, good, record, function() { return true; });
expect(mixed_id != null && generation.read_generation(gen, 'source', mixed_id).legacy_revision == record.legacy_revision,
    'mixed legacy hash was not retained');
record.mode = 'only';
expect(index(fs.readfile(gen + '/source-' + first_id + '.json'), key) < 0, 'key in generation');
expect(store.save(candidates, 'source', id, 'vpn://' + b64enc(replace(config, 'example.invalid', 'second.invalid'))), 'second candidate');
let second = store.revision(candidates, 'source', id);
expect(store.promote(candidates, good, 'source', id, second), 'second promotion');
record.revision = second; record.entries = [{index:0,name:'afawg_2',table:'15002',priority:'16004'}];
let second_id = generation.stage(gen, good, record, function() { return true; });
expect(second_id != null && !generation.switch_to(gen, 'source', null, second_id), 'unexpected pointer overwrite');
let verify_opts = { matches_source:function() { return true; }, uci_check:function() { return {ok:true}; }, live_check:function() { return {ok:true}; } };
expect(generation_restore.inspect(gen, good, 'source', second_id, null, 1000, verify_opts).generation == second_id &&
    generation_restore.restore(gen, good, 'source', null, 1000, verify_opts).generation == first_id,
    'staged generation inspected by changing current pointer');
expect(journal.write(jdir, 'source', first_id, second_id, 'prepared'), 'journal prepare');
expect(journal.recovery(jdir, gen, 'source').action == 'restore', 'prepared crash recovery');
expect(journal.bind_snapshots(jdir, 'source', first_id, second_id, first_id, second_id), 'snapshot binding');
expect(journal.write(jdir, 'source', first_id, second_id, 'union'), 'journal union');
expect(generation.switch_to(gen, 'source', first_id, second_id), 'atomic pointer switch');
expect(journal.recovery(jdir, gen, 'source').action == 'restore', 'crash between pointer and journal');
expect(journal.write(jdir, 'source', first_id, second_id, 'published'), 'journal published');
expect(journal.recovery(jdir, gen, 'source').action == 'restore', 'unverified generation accepted');
expect(journal.write(jdir, 'source', first_id, second_id, 'verified'), 'journal verified');
expect(journal.recovery(jdir, gen, 'source').action == 'finish', 'verified crash recovery');
expect(!journal.write(jdir, 'source', first_id, second_id, 'prepared'), 'journal phase rollback');
expect(generation.switch_to(gen, 'source', second_id, first_id), 'old generation restoration');
expect(journal.recovery(jdir, gen, 'source').action == 'restore', 'old pointer recovery');
let jdir2 = base + '/journal2';
expect(fs.mkdir(jdir2), 'second journal fixture');
let ops = {};
for (let n in ['prepare','install_union','verify_union','reload','verify_new','restore_old','verify_old','discard_new','retire_old'])
    ops[n] = function() { return true; };
ops.snapshot_revisions = function() { return {old:first_id, new:second_id}; };
ops.retire_old = function() { return false; };
let switched = swap.execute_journaled(ops, jdir2, gen, 'source', first_id, second_id);
expect(switched.ok && switched.cleanup_required && generation.current_id(gen, 'source') == second_id && journal.read(jdir2, 'source').phase == 'verified', 'journaled swap');
ops.retire_old = function() { return true; };
expect(swap.recover(ops, jdir2, gen, 'source').action == 'finished', 'completed swap recovery');
expect(journal.read(jdir2, 'source') == null, 'recovered journal was not removed');
let jdir3 = base + '/journal3';
expect(fs.mkdir(jdir3), 'third journal fixture');
ops.reload = function() { return false; };
let rollback = swap.execute_journaled(ops, jdir3, gen, 'source', second_id, first_id);
expect(!rollback.ok && !rollback.recovery_required && generation.current_id(gen, 'source') == second_id &&
    journal.read(jdir3, 'source') == null, 'failed switch did not restore old pointer and clear journal');
let jdir4 = base + '/journal4';
expect(fs.mkdir(jdir4), 'fourth journal fixture');
let events = [];
let locks = {
    acquire_reload:function() { push(events, 'reload+'); return true; },
    acquire_subscription:function() { push(events, 'subscription+'); return true; },
    with_awg:function(o, cb) { push(events, 'awg+'); let r = cb({ marker:'lease', valid:function() { return true; } }); push(events, 'awg-'); return r; },
    owned:function() { return true; },
    release_subscription:function() { push(events, 'subscription-'); return true; },
    release_reload:function() { push(events, 'reload-'); return true; }
};
ops.reload = function() { return true; };
ops.snapshot_revisions = function() { return {old:second_id, new:first_id}; };
let orchestrated = orchestrator.execute(function(lease) { expect(lease.marker == 'lease', 'lease missing'); return ops; },
    jdir4, gen, 'source', second_id, first_id, {locks});
expect(orchestrated.ok && generation.current_id(gen, 'source') == first_id &&
    join(',', events) == 'reload+,subscription+,awg+,awg-,subscription-,reload-', 'orchestration lock order or switch');
events = [];
let recovered = orchestrator.recover(function() { return ops; }, jdir, gen, 'source', {locks});
expect(recovered.ok && recovered.action == 'restored' && journal.read(jdir, 'source') == null &&
    join(',', events) == 'reload+,subscription+,awg+,awg-,subscription-,reload-', 'journal recovery did not hold transition locks');
events = [];
locks.acquire_subscription = function() { push(events, 'subscription+'); return false; };
let no_lock = orchestrator.execute(function() { die('factory must not run'); }, jdir4, gen, 'source', first_id, second_id, {locks});
expect(!no_lock.ok && join(',', events) == 'reload+,subscription+,reload-', 'lock failure cleanup');
events = [];
locks.acquire_subscription = function() { push(events, 'subscription+'); return true; };
locks.with_awg = function() { push(events, 'awg+'); die('sensitive exception fixture'); };
let thrown = orchestrator.execute(function() { return ops; }, jdir4, gen, 'source', first_id, second_id, {locks});
expect(!thrown.ok && join(',', events) == 'reload+,subscription+,awg+,subscription-,reload-' &&
    index(sprintf('%J', thrown), 'sensitive exception fixture') < 0, 'exception handling or lock cleanup');
let jdir5 = base + '/journal5';
expect(fs.mkdir(jdir5) && journal.write(jdir5, 'source', first_id, second_id, 'prepared'), 'permissions journal fixture');
print('AWG atomic generation and crash journal checks passed\n');
