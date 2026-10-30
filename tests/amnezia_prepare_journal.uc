let fs = require('fs');
let store = require('subscription.amnezia_store');
let identity = require('subscription.amnezia_identity');
let generation = require('subscription.amnezia_generation');
let prepare = require('subscription.amnezia_prepare_journal');
let prepare_apply = require('subscription.amnezia_prepare_apply');
function expect(v, msg) { if (!v) die('FAIL: ' + msg + '\n'); }
let base = ARGV[0], cand = base + '/candidate', good = base + '/good', gen = base + '/generation', journal = base + '/prepare';
expect(fs.mkdir(cand) && fs.mkdir(good) && fs.mkdir(gen) && fs.mkdir(journal), 'fixture dirs');
let key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
let conf = '[Interface]\nPrivateKey = ' + key + '\nAddress = 10.0.0.2/32\n' +
    '[Peer]\nPublicKey = ' + key + '\nEndpoint = awg.example.invalid:443\nAllowedIPs = 0.0.0.0/0\n';
let id = identity.calculate(cand, 'source', 'https://example.invalid/sub', 'agent', 'device');
let link = 'vpn://' + b64enc(conf);
expect(store.save(cand, 'source', id, link), 'old candidate');
let oldrev = store.revision(cand, 'source', id);
expect(store.promote(cand, good, 'source', id, oldrev), 'old promotion');
let old = generation.stage(gen, good, {version:1, source:'source', identity:id, revision:oldrev,
    url:'https://example.invalid/sub', user_agent:'agent', hwid:'device',
    entries:[{index:0,name:'afawg_1',table:'15001',priority:'16002'}]}, function() { return true; });
expect(old != null && generation.switch_to(gen, 'source', null, old), 'old active generation');
expect(store.save(cand, 'source', id, link + '\n' + link), 'new candidate');
let revision = store.revision(cand, 'source', id);
let entries = [{index:0,name:'afawg_2',table:'15002',priority:'16004',private_key:key},
    {index:1,name:'afawg_3',table:'15003',priority:'16006'}];
expect(prepare.create(journal, gen, cand, good, 'source', old, id, revision, entries), 'create reservation');
expect(!prepare.create(journal, gen, cand, good, 'source', old, id, revision, entries), 'reservation overwritten');
expect(store.revision(good + '/' + revision, 'source', id) == revision, 'reserved candidate not preserved');
expect(index(fs.readfile(journal + '/source.prepare.json'), key) < 0, 'private key leaked');
expect(!prepare.begin(journal, 'source', 1), 'out-of-order begin');
expect(prepare.begin(journal, 'source', 0), 'first begin');
expect(prepare.read(journal, 'source').inflight == 0, 'in-flight recovery state missing');
expect(!prepare.begin(journal, 'source', 1) && !prepare.finish(journal, 'source', 1), 'in-flight checkpoint bypassed');
expect(prepare.finish(journal, 'source', 0), 'first finish');
expect(prepare.read(journal, 'source').completed == 1 && prepare.read(journal, 'source').inflight == null, 'completed checkpoint');
expect(prepare.begin(journal, 'source', 1) && prepare.finish(journal, 'source', 1), 'second checkpoint');
expect(prepare.read(journal, 'source').completed == 2 && !prepare.begin(journal, 'source', 2), 'completed plan overrun');
let journal2 = base + '/prepare2';
expect(fs.mkdir(journal2), 'second journal dir');
let planned = prepare.reserve(journal2, gen, cand, good, 'source', old, id, null,
    { choose_many:function(cursor, count) { return {ok:count == 2, allocations:entries}; } });
expect(planned != null && length(planned.entries) == 2 && planned.completed == 0, 'batch allocator did not persist plan');
expect(index(sprintf('%J', planned), key) < 0, 'reservation result leaked key');
let count = 0;
let lease = { apply:function() { count++; return {ok:true}; } };
let metadata = { url:'https://example.invalid/sub', user_agent:'agent', hwid:'device' };
let options = { current:function() { return true; }, cursor:{ load:function() { return true; } },
    uci_check:function() { return {ok:true}; }, live_check:function() { return {ok:true}; } };
let staged = prepare_apply.run(lease, journal2, gen, good, 'source', metadata, 1000, options);
expect(staged.ok && count == 2 && generation.current_id(gen, 'source') == old &&
    prepare.read(journal2, 'source').completed == 2 && generation.read_generation(gen, 'source', staged.generation) != null,
    'batch preparation did not retain old active generation');
let journal3 = base + '/prepare3';
expect(fs.mkdir(journal3), 'third journal dir');
expect(prepare.reserve(journal3, gen, cand, good, 'source', old, id, null,
    { choose_many:function() { return {ok:true, allocations:entries}; } }) != null, 'failure plan');
count = 0;
lease.apply = function() { count++; return {ok:count == 1}; };
let failed = prepare_apply.run(lease, journal3, gen, good, 'source', metadata, 1000, options);
expect(!failed.ok && failed.recovery_required && prepare.read(journal3, 'source').completed == 1 &&
    prepare.read(journal3, 'source').inflight == 1 && generation.current_id(gen, 'source') == old,
    'failed apply did not preserve uncertain checkpoint and old generation');
let cleaned = 0;
let recovery_lease = { valid:function() { return true; }, cleanup:function() { cleaned++; return {ok:true}; } };
let recovery_options = { holds:function() { return true; }, verify_old:function() { return false; }, is_absent:function() { return false; } };
let recovery = require('subscription.amnezia_prepare_cleanup');
expect(!recovery.cleanup(recovery_lease, journal3, gen, good, 'source', recovery_options).ok && cleaned == 0,
    'unverified old runtime allowed cleanup');
recovery_options.verify_old = function() { return true; };
expect(recovery.cleanup(recovery_lease, journal3, gen, good, 'source', recovery_options).ok && cleaned == 2 &&
    fs.stat(journal3 + '/source.prepare.json') == null, 'prepare recovery did not clean both interfaces');
let swapdir = base + '/swap';
expect(fs.mkdir(swapdir), 'swap journal dir');
expect(!prepare.handoff(journal3, swapdir, gen, 'source', staged.generation), 'in-flight plan handed off');
expect(prepare.handoff(journal2, swapdir, gen, 'source', staged.generation), 'completed plan not handed off');
expect(fs.stat(journal2 + '/source.prepare.json') == null &&
    require('subscription.amnezia_swap_journal').read(swapdir, 'source').phase == 'prepared' &&
    generation.current_id(gen, 'source') == old, 'handoff did not preserve old generation and journal');
let ops = {};
for (let n in ['prepare','install_union','verify_union','reload','verify_new','restore_old','verify_old','discard_new','retire_old'])
    ops[n] = function() { return true; };
ops.snapshot_revisions = function() { return {old:old, new:staged.generation}; };
expect(require('subscription.amnezia_swap').execute_journaled(ops, swapdir, gen, 'source', old, staged.generation).ok &&
    generation.current_id(gen, 'source') == staged.generation, 'prepared handoff not accepted by swap');
expect(store.save(cand, 'source', id, 'vpn://' + b64enc(replace(conf, 'example.invalid', 'third.invalid'))), 'third candidate');
let journal4 = base + '/transaction';
expect(fs.mkdir(journal4), 'transaction directory');
let locks = { acquire_reload:function() { return true; }, acquire_subscription:function() { return true; },
    release_subscription:function() { return true; }, release_reload:function() { return true; }, owned:function() { return true; },
    with_awg:function(o, cb) { return cb({ valid:function() { return true; }, apply:function() { return {ok:true}; } }); } };
let transaction_opts = { locks, current:function() { return true; }, cursor:options.cursor, uci_check:options.uci_check, live_check:options.live_check,
    choose_many:function() { return {ok:true, allocations:[{name:'afawg_4',table:'15004',priority:'16008'}]}; } };
let transition = require('subscription.amnezia_orchestrator').prepare_and_execute(function(lease, holds, new_id) {
    let hooks = {};
    for (let n in ['prepare','install_union','verify_union','reload','verify_new','restore_old','verify_old','discard_new','retire_old'])
        hooks[n] = function() { return holds(); };
    hooks.snapshot_revisions = function() { return {old:staged.generation, new:new_id}; };
    return hooks;
}, {journal:journal4,generation:gen,candidate:cand,good}, 'source', staged.generation, id, metadata, 1000, transaction_opts);
expect(transition.ok && generation.current_id(gen, 'source') != staged.generation &&
    fs.stat(journal4 + '/source.prepare.json') == null && fs.stat(journal4 + '/source.swap.json') == null,
    'end-to-end prepared update failed');
print('AWG pre-commit reservation and crash checkpoints passed\n');
