// Validate immutable recovery inputs before constructing any nft candidate.
// This is a plan only: caller must hold all locks, ensure sing-box cannot send
// unguarded traffic, audit mark conflicts, install the entire candidate, then
// verify the real firewall and route state before starting/reusing the core.
let journal = require('subscription.amnezia_swap_journal');
let generation = require('subscription.amnezia_generation');
let snapshot = require('subscription.amnezia_snapshot');
let union = require('subscription.amnezia_guard_union');
function matches(snapshot_record, generation_record, source) {
    if (type(snapshot_record) != 'object' || type(snapshot_record.entries) != 'array' ||
        type(generation_record) != 'object' || generation_record.source != source || type(generation_record.entries) != 'array') return false;
    let count = 0;
    for (let e in snapshot_record.entries) {
        if (e.source != source) continue;
        let found = false;
        for (let item in generation_record.entries)
            if (e.index == item.index && e.name == item.name && e.table == item.table && e.priority == item.priority &&
                e.identity == generation_record.identity && e.revision == generation_record.revision) found = true;
        if (!found) return false;
        count++;
    }
    return count == length(generation_record.entries) && count > 0;
}
function plan(journal_dir, generation_dir, snapshot_base, source, opts) {
    opts = type(opts) == 'object' ? opts : {};
    let read_journal = opts.read_journal || journal.read, current_id = opts.current_id || generation.current_id;
    let read_generation = opts.read_generation || generation.read_generation, load = opts.load || snapshot.load;
    try {
        let j = read_journal(journal_dir, source);
        if (type(j) != 'object' || j.source != source || index(['union','published','rollback','verified','retired'], j.phase) < 0 ||
            type(j.old_snapshot) != 'string' || !match(j.old_snapshot, /^[0-9a-f]{64}$/) ||
            type(j.new_snapshot) != 'string' || !match(j.new_snapshot, /^[0-9a-f]{64}$/)) return null;
        let pointer = current_id(generation_dir, source);
        if (pointer != j.old_generation && pointer != j.new_generation) return null;
        let old_dir = snapshot_base + '/' + j.old_snapshot, new_dir = snapshot_base + '/' + j.new_snapshot;
        let a = load(old_dir), b = load(new_dir);
        if (a?.revision != j.old_snapshot || b?.revision != j.new_snapshot ||
            !matches(a, read_generation(generation_dir, source, j.old_generation), source) ||
            !matches(b, read_generation(generation_dir, source, j.new_generation), source)) return null;
        let guard = union.plan(a.entries, b.entries, []);
        if (!guard.ok || !length(guard.guards)) return null;
        let again = read_journal(journal_dir, source);
        if (sprintf('%J', j) != sprintf('%J', again) || current_id(generation_dir, source) != pointer ||
            load(old_dir)?.revision != j.old_snapshot || load(new_dir)?.revision != j.new_snapshot) return null;
        return {ok:true,source,phase:j.phase,old_generation:j.old_generation,new_generation:j.new_generation,
            old_snapshot:j.old_snapshot,new_snapshot:j.new_snapshot,old_snapshot_dir:old_dir,new_snapshot_dir:new_dir,
            action:(j.phase == 'verified' || j.phase == 'retired') && pointer == j.new_generation ? 'finish' : 'restore', guards:guard.guards};
    } catch (e) { return null; }
}
return { plan };
