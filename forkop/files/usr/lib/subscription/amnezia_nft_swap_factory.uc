// An in-process, lock-bound candidate transaction for a journaled AWG swap.
// Trusted lifecycle callbacks provide the real nft operations; no process or
// recursive Forkop reload is started here. The caller owns all locks.
let journal = require('subscription.amnezia_swap_journal');
let generation = require('subscription.amnezia_generation');
let snapshot = require('subscription.amnezia_snapshot');
function create(ctx, hooks) {
    if (type(ctx) != 'object' || type(hooks) != 'object') return null;
    for (let name in ['holds_locks','lease_active','begin','rebuild_base','install_guards',
        'apply_lists','validate','commit','abort','verify_union'])
        if (type(hooks[name]) != 'function') return null;
    let read_journal = hooks.read_journal || journal.read;
    let current_id = hooks.current_id || generation.current_id;
    let load = hooks.load || snapshot.load;
    function stable(phase) {
        try {
            if (hooks.holds_locks() !== true || hooks.lease_active() !== true) return false;
            let j = read_journal(ctx.journal_dir, ctx.source);
            let old = load(ctx.old_snapshot_dir), next = load(ctx.new_snapshot_dir);
            return type(j) == 'object' && j.source == ctx.source && j.phase == phase &&
                j.old_generation == ctx.old_generation && j.new_generation == ctx.new_generation &&
                j.old_snapshot == ctx.old_snapshot && j.new_snapshot == ctx.new_snapshot &&
                current_id(ctx.generation_dir, ctx.source) == (phase == 'prepared' || phase == 'union' ? ctx.old_generation : ctx.new_generation) &&
                old?.revision == ctx.old_snapshot && next?.revision == ctx.new_snapshot;
        } catch (e) { return false; }
    }
    function install_union() {
        let begun = false, committed = false;
        function run() {
          try {
            if (!stable('prepared') || hooks.begin() !== true) return false;
            begun = true;
            // Rebuild the complete base table and all list-backed sets. An
            // incomplete candidate must never replace the live dataplane.
            if (hooks.rebuild_base() !== true || hooks.install_guards(ctx) !== true ||
                hooks.apply_lists() !== true || hooks.validate() !== true || !stable('prepared')) return false;
            if (hooks.commit() !== true) return false;
            committed = true;
            return stable('prepared');
          } catch (e) { return false; }
        }
        let result = run();
        // Abort must only discard temporary candidate files; it must not
        // modify the live table even when a commit had an uncertain result.
        if (begun && !committed) try { hooks.abort(); } catch (ignored) {}
        return result;
    }
    function verify_union() {
        if (!stable('union')) return false;
        try { return hooks.verify_union(ctx) === true && stable('union'); } catch (e) { return false; }
    }
    return { install_union, verify_union };
}
return { create };
