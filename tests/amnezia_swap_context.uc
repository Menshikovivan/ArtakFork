let fs = require('fs');
let snapshot = require('subscription.amnezia_snapshot');
let journal = require('subscription.amnezia_swap_journal');
let context = require('subscription.amnezia_swap_context');
let publish = require('subscription.amnezia_snapshot_publish');
function expect(v, m) { if (!v) die('FAIL: ' + m + '\n'); }
let base = ARGV[0], jdir = base + '/journal', gen = base + '/generation', root = base + '/snapshots';
expect(fs.mkdir(jdir) && fs.mkdir(gen) && fs.mkdir(root), 'fixture directories');
let old_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let new_id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
let id = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
let e = {index:0,name:'afawg_1',table:'15001',priority:'16002',mark:0x18000000 | 15001,source:'source',identity:id,revision:old_id};
let temp_old = base + '/old', temp_new = base + '/new';
expect(fs.mkdir(temp_old) && fs.mkdir(temp_new), 'snapshot temp dirs');
let a = snapshot.save(temp_old, [e]);
e.name = 'afawg_2'; e.table = '15002'; e.priority = '16004'; e.mark = 0x18000000 | 15002; e.revision = new_id;
let b = snapshot.save(temp_new, [e]);
expect(a != null && b != null && publish.publish(temp_old, root) == a.revision && publish.publish(temp_new, root) == b.revision &&
    publish.publish(temp_old, root) == a.revision, 'snapshot publication');
expect(fs.writefile(gen + '/source.current', old_id + '\n') != null && journal.write(jdir, 'source', old_id, new_id, 'prepared') &&
    journal.bind_snapshots(jdir, 'source', old_id, new_id, a.revision, b.revision), 'journal setup');
let opts = {verify:function() { return {ok:true, guards:[]}; }};
expect(!context.select(jdir, gen, root, 'source', opts).ok, 'prepared journal accepted');
expect(journal.write(jdir, 'source', old_id, new_id, 'union'), 'union phase');
let selected = context.select(jdir, gen, root, 'source', opts);
expect(selected.ok && selected.transition && selected.snapshot.revision == a.revision, 'old snapshot selection');
expect(fs.writefile(gen + '/source.current', new_id + '\n') != null && !context.select(jdir, gen, root, 'source', opts).ok,
    'uncommitted generation switch accepted');
expect(journal.write(jdir, 'source', old_id, new_id, 'published'), 'published phase');
expect(context.select(jdir, gen, root, 'source', opts).snapshot.revision == b.revision, 'new snapshot selection');
expect(context.select_any(jdir, gen, root, opts).snapshot.revision == b.revision, 'global transition snapshot selection');
expect(fs.writefile(jdir + '/other.swap.json', '{}') != null && !context.select_any(jdir, gen, root, opts).ok, 'multiple concurrent journals accepted');
fs.unlink(jdir + '/other.swap.json');
expect(journal.mark_rollback(jdir, 'source', old_id, new_id), 'rollback phase');
expect(!context.select_any(jdir, gen, root, opts).ok, 'rollback accepted new pointer');
expect(fs.writefile(gen + '/source.current', old_id + '\n') != null && context.select_any(jdir, gen, root, opts).snapshot.revision == a.revision,
    'rollback did not select old snapshot');
fs.unlink(jdir + '/source.swap.json');
expect(journal.write(jdir, 'source', old_id, new_id, 'prepared') && journal.bind_snapshots(jdir, 'source', old_id, new_id, a.revision, b.revision) &&
    journal.write(jdir, 'source', old_id, new_id, 'union') && fs.writefile(gen + '/source.current', new_id + '\n') != null &&
    journal.write(jdir, 'source', old_id, new_id, 'published') && journal.write(jdir, 'source', old_id, new_id, 'verified') &&
    journal.write(jdir, 'source', old_id, new_id, 'retired'), 'retired journal setup');
expect(context.select_any(jdir, gen, root, opts).snapshot.revision == b.revision, 'retired did not select new snapshot');
opts.verify = function() { return {ok:false}; };
expect(!context.select(jdir, gen, root, 'source', opts).ok, 'missing union guard accepted');
print('AWG union generation context checks passed\n');
