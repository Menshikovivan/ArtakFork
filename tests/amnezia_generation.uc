let fs = require('fs');
let store = require('subscription.amnezia_store');
let ident = require('subscription.amnezia_identity');
let generation = require('subscription.amnezia_generation');
let journal = require('subscription.amnezia_swap_journal');
let swap = require('subscription.amnezia_swap');
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
expect(index(fs.readfile(gen + '/source-' + first_id + '.json'), key) < 0, 'key in generation');
expect(store.save(candidates, 'source', id, 'vpn://' + b64enc(replace(config, 'example.invalid', 'second.invalid'))), 'second candidate');
let second = store.revision(candidates, 'source', id);
expect(store.promote(candidates, good, 'source', id, second), 'second promotion');
record.revision = second; record.entries = [{index:0,name:'afawg_2',table:'15002',priority:'16004'}];
let second_id = generation.stage(gen, good, record, function() { return true; });
expect(second_id != null && !generation.switch_to(gen, 'source', null, second_id), 'unexpected pointer overwrite');
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
print('AWG atomic generation and crash journal checks passed\n');
