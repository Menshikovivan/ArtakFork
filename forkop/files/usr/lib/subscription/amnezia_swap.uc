// Internal transaction state machine for replacing an active AWG source.
// Hooks are trusted in-process implementations invoked while subscription,
// network and firewall lifecycle locks are held. This state machine does not
// itself persist a crash journal and must not be used by production until the
// lifecycle provides durable recovery and a firewall guard for both sets.
// Hook errors and connection data are never returned or logged.
function execute(ops) {
    let required = ['prepare', 'install_union', 'verify_union', 'publish',
        'reload', 'verify_new', 'restore_old', 'verify_old', 'discard_new', 'retire_old'];
    if (type(ops) != 'object') return { ok:false, error:'Invalid swap transaction' };
    for (let name in required)
        if (type(ops[name]) != 'function') return { ok:false, error:'Incomplete swap transaction' };
    let prepared = false, union_installed = false, published = false, previous_restored = true;
    function call(name) { try { return ops[name]() === true; } catch (e) { return false; } }
    function fail(message) {
        if (published) {
            previous_restored = call('restore_old') && call('verify_old');
        } else previous_restored = call('verify_old');
        // Preserve the union guard and new resources if the old route could
        // not be verified; deleting them here could cut off or expose traffic.
        let cleaned = false;
        if (prepared && previous_restored) cleaned = call('discard_new');
        return { ok:false, error:message, recovery_required:!previous_restored || (prepared && !cleaned), union_installed };
    }
    if (!call('prepare')) return { ok:false, error:'Could not prepare new AWG profiles', recovery_required:true };
    prepared = true;
    if (!call('install_union')) return fail('Could not install union guard');
    union_installed = true;
    if (!call('verify_union')) return fail('Union guard verification failed');
    published = true;
    if (!call('publish')) return fail('Could not publish new AWG profiles');
    if (!call('reload') || !call('verify_new')) return fail('Could not verify new AWG routing');
    // Failure to retire old profiles must not tear down verified new routing.
    if (!call('retire_old')) return { ok:true, cleanup_required:true };
    return { ok:true, cleanup_required:false };
}

// Coordinates one atomic generation pointer with the durable phase journal.
// Callers supply lifecycle hooks that establish/verify guard and sing-box;
// these hooks are not implemented here. Run only under all lifecycle locks.
function execute_journaled(ops, journal_dir, generation_dir, source, old_id, new_id) {
    let journal = require('subscription.amnezia_swap_journal');
    let gen = require('subscription.amnezia_generation');
    if (gen.current_id(generation_dir, source) != old_id ||
        gen.read_generation(generation_dir, source, old_id) == null ||
        gen.read_generation(generation_dir, source, new_id) == null)
        return { ok:false, error:'Cannot start journaled swap' };
    let existing = journal.read(journal_dir, source);
    if (existing == null) {
        if (!journal.write(journal_dir, source, old_id, new_id, 'prepared')) return { ok:false, error:'Cannot start journaled swap' };
    } else if (existing.phase != 'prepared' || existing.old_generation != old_id || existing.new_generation != new_id ||
        existing.old_snapshot != null || existing.new_snapshot != null) return { ok:false, error:'Swap journal is not ready' };
    function phase(name) { return journal.write(journal_dir, source, old_id, new_id, name); }
    let wrapped = {
        prepare: function() {
            if (ops.prepare() !== true || type(ops.snapshot_revisions) != 'function') return false;
            let snapshots = ops.snapshot_revisions();
            return type(snapshots) == 'object' && journal.bind_snapshots(journal_dir, source, old_id, new_id, snapshots.old, snapshots.new);
        },
        install_union: function() { return ops.install_union() === true && phase('union'); },
        verify_union: function() { return ops.verify_union() === true; },
        publish: function() { return gen.switch_to(generation_dir, source, old_id, new_id) && phase('published'); },
        reload: function() { return ops.reload() === true; },
        verify_new: function() { return ops.verify_new() === true && phase('verified'); },
        restore_old: function() {
            if (!journal.mark_rollback(journal_dir, source, old_id, new_id)) return false;
            let current = gen.current_id(generation_dir, source);
            if (current == new_id && !gen.switch_to(generation_dir, source, new_id, old_id)) return false;
            if (current != old_id && current != new_id) return false;
            return ops.restore_old() === true;
        },
        verify_old: function() { return ops.verify_old() === true; },
        discard_new: function() { return ops.discard_new() === true; },
        retire_old: function() {
            if (ops.retire_old() !== true || !phase('retired')) return false;
            return type(ops.finalize_new) != 'function' || ops.finalize_new() === true;
        }
    };
    let result = execute(wrapped);
    if (result.ok && !result.cleanup_required) {
        if (!journal.clear(journal_dir, source, old_id, new_id, function() { return ops.verify_new() === true; }))
            return { ok:true, cleanup_required:true };
    } else if (!result.ok && !result.recovery_required && gen.current_id(generation_dir, source) == old_id) {
        if (!journal.clear(journal_dir, source, old_id, new_id, function() { return ops.verify_old() === true; }))
            result.recovery_required = true;
    }
    return result;
}

// Recovery is deliberately conservative: old/new resources are deleted only
// after the chosen runtime and its guard are verified by trusted lifecycle
// hooks. Journal removal is a separate operation after full reconciliation.
function recover(ops, journal_dir, generation_dir, source) {
    let journal = require('subscription.amnezia_swap_journal');
    let gen = require('subscription.amnezia_generation');
    let record = journal.read(journal_dir, source), plan = journal.recovery(journal_dir, generation_dir, source);
    if (record == null || plan == null || plan.action == 'inspect' || type(ops) != 'object')
        return { ok:false, error:'Swap recovery needs inspection' };
    try {
        if (plan.action == 'restore') {
            let current = gen.current_id(generation_dir, source);
            if (record.phase != 'prepared' && !journal.mark_rollback(journal_dir, source, record.old_generation, record.new_generation))
                return { ok:false, error:'Cannot record rollback phase' };
            if (current == record.new_generation && !gen.switch_to(generation_dir, source, current, record.old_generation))
                return { ok:false, error:'Cannot restore old generation' };
            if (ops.restore_old() !== true || ops.verify_old() !== true || ops.discard_new() !== true)
                return { ok:false, error:'Cannot safely restore old routing' };
            if (!journal.clear(journal_dir, source, record.old_generation, record.new_generation, function() { return ops.verify_old() === true; }))
                return { ok:false, error:'Cannot clear recovered journal' };
            return { ok:true, action:'restored' };
        }
        if (ops.verify_new() !== true || ops.retire_old() !== true)
            return { ok:false, error:'Cannot safely finish new routing' };
        if (record.phase == 'verified' && !journal.write(journal_dir, source, record.old_generation, record.new_generation, 'retired'))
            return { ok:false, error:'Cannot record swap cleanup' };
        if (type(ops.finalize_new) == 'function' && ops.finalize_new() !== true)
            return { ok:false, error:'Cannot finalize new routing' };
        if (!journal.clear(journal_dir, source, record.old_generation, record.new_generation, function() { return ops.verify_new() === true; }))
            return { ok:false, error:'Cannot clear finished journal' };
        return { ok:true, action:'finished' };
    } catch (e) { return { ok:false, error:'Swap recovery failed' }; }
}
return { execute, execute_journaled, recover };
