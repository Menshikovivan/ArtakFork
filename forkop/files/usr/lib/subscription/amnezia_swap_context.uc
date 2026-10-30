// Select the immutable snapshot associated with the active journal phase. The
// caller provides trusted, fixed root-owned directories, never user-supplied
// paths. The union verifier checks both generations and the installed guard.
let fs = require('fs');
let journal = require('subscription.amnezia_swap_journal');
let snapshot = require('subscription.amnezia_snapshot');
let verifier = require('subscription.amnezia_guard_union_verify');
let generation = require('subscription.amnezia_generation');
function select(journal_dir, generation_dir, snapshot_base, source, opts) {
    opts = type(opts) == 'object' ? opts : {};
    if (type(source) != 'string' || !match(source, /^[A-Za-z0-9_-]{1,100}$/)) return {ok:false};
    let path = journal_dir + '/' + source + '.swap.json';
    if (fs.lstat(path) == null) return {ok:true, transition:false};
    let j = journal.read(journal_dir, source);
    if (j == null || index(['union','published','verified','rollback','retired'], j.phase) < 0 ||
        type(j.old_snapshot) != 'string' || !match(j.old_snapshot, /^[0-9a-f]{64}$/) ||
        type(j.new_snapshot) != 'string' || !match(j.new_snapshot, /^[0-9a-f]{64}$/)) return {ok:false};
    let old_dir = snapshot_base + '/' + j.old_snapshot, new_dir = snapshot_base + '/' + j.new_snapshot;
    let old_stat = fs.lstat(old_dir), new_stat = fs.lstat(new_dir);
    if (old_stat?.type != 'directory' || new_stat?.type != 'directory') return {ok:false};
    let check = type(opts.verify) == 'function' ? opts.verify : verifier.verify;
    let checked = check(journal_dir, generation_dir, source, old_dir, new_dir, opts.verifier_opts);
    if (type(checked) != 'object' || checked.ok !== true) return {ok:false};
    let use_old = j.phase == 'union' || j.phase == 'rollback';
    let selected = snapshot.load(use_old ? old_dir : new_dir);
    let expected = use_old ? j.old_snapshot : j.new_snapshot;
    let after = journal.read(journal_dir, source);
    let pointer = generation.current_id(generation_dir, source);
    let expected_generation = use_old ? j.old_generation : j.new_generation;
    if (selected == null || selected.revision != expected || after == null || sprintf('%J', after) != sprintf('%J', j) ||
        pointer != expected_generation) return {ok:false};
    return {ok:true, transition:true, snapshot:selected, guards:checked.guards};
}
function definitely_missing(path, depth) {
    if (depth > 8 || type(path) != 'string' || path == '' || path == '/') return false;
    let parts = match(path, /^(.*)\/([^\/]+)$/);
    if (parts == null || parts[1] == '' || parts[2] == '.' || parts[2] == '..') return false;
    let parent = fs.lstat(parts[1]);
    if (parent == null) return definitely_missing(parts[1], depth + 1);
    if (parent.type != 'directory') return false;
    let names = fs.lsdir(parts[1]);
    return type(names) == 'array' && index(names, parts[2]) < 0;
}
// One global transaction controls the entire nft chain, including outbounds
// from other subscriptions. Multiple/incomplete journals fail closed.
function select_any(journal_dir, generation_dir, snapshot_base, opts) {
    let st = fs.lstat(journal_dir);
    if (st == null) return definitely_missing(journal_dir, 0) ? {ok:true,transition:false} : {ok:false};
    if (st.type != 'directory') return {ok:false};
    let names = fs.lsdir(journal_dir);
    if (type(names) != 'array') return {ok:false};
    let source = null;
    for (let name in names) {
        if (match(name, /\.prepare\.json$/)) return {ok:false};
        if (!match(name, /\.swap\.json$/)) continue;
        let parsed = match(name, /^([A-Za-z0-9_-]{1,100})\.swap\.json$/);
        if (parsed == null || source != null) return {ok:false};
        source = parsed[1];
    }
    return source == null ? {ok:true,transition:false} : select(journal_dir, generation_dir, snapshot_base, source, opts);
}
return { select, select_any };
