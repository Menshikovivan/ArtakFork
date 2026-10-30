// Recover a pre-commit journal under the same transition locks. No interface
// is removed until the old runtime and guard have been independently verified.
let fs = require('fs');
let journal = require('subscription.amnezia_prepare_journal');
let generation = require('subscription.amnezia_generation');
let store = require('subscription.amnezia_store');
let activation = require('subscription.amnezia_activate');
function absent(entry, opts) {
    let cursor = opts.cursor || require('uci').cursor();
    if (!cursor || cursor.load('network') == null) return false;
    for (let suffix in ['', '_peer', '_rt4', '_rl4', '_deny4', '_rt6', '_rl6', '_deny6'])
        if (cursor.get('network', entry.name + suffix) != null) return false;
    let runner = type(opts.runner) == 'function' ? opts.runner : activation.run;
    let response = runner(['ip', '-j', 'link', 'show']), links;
    if (type(response) != 'object' || !response.ok) return false;
    try { links = json(response.output); } catch (e) { return false; }
    if (type(links) != 'array') return false;
    for (let link in links) {
        if (type(link) != 'object' || type(link.ifname) != 'string' || link.ifname == entry.name) return false;
    }
    return true;
}
function cleanup(lease, journal_dir, generation_dir, good_dir, source, opts) {
    opts = type(opts) == 'object' ? opts : {};
    if (type(lease) != 'object' || type(lease.cleanup) != 'function' || type(lease.valid) != 'function' ||
        type(opts.verify_old) != 'function' || type(opts.holds) != 'function') return {ok:false,error:'Recovery requires verified ownership'};
    let plan = journal.read(journal_dir, source);
    if (plan == null) return {ok:false,error:'Prepare journal invalid'};
    let path = good_dir + '/' + plan.revision;
    let configs = store.load_configs(path, source, plan.identity);
    if (type(configs) != 'array' || length(configs) != length(plan.entries) ||
        store.revision(path, source, plan.identity) != plan.revision) return {ok:false,error:'Recovery candidate unavailable'};
    let is_absent = type(opts.is_absent) == 'function' ? opts.is_absent : absent;
    function old_ready() {
        try { return lease.valid() === true && opts.holds() === true &&
            generation.current_id(generation_dir, source) == plan.old_generation && opts.verify_old() === true; }
        catch (e) { return false; }
    }
    if (!old_ready()) return {ok:false,error:'Old runtime not verified'};
    let count = plan.completed + (plan.inflight == null ? 0 : 1);
    try {
        for (let i = count - 1; i >= 0; i--) {
            if (!old_ready()) return {ok:false,error:'Old runtime or locks changed'};
            let entry = plan.entries[i];
            if (is_absent(entry, opts) === true) continue;
            let result = lease.cleanup(configs[i], entry.name, entry.table, entry.priority);
            if (type(result) != 'object' || result.ok !== true) return {ok:false,error:'Cannot remove prepared interface'};
        }
        if (!old_ready() || store.revision(path, source, plan.identity) != plan.revision) return {ok:false,error:'Old runtime or candidate changed'};
        let now = journal.read(journal_dir, source);
        if (now == null || sprintf('%J', now) != sprintf('%J', plan)) return {ok:false,error:'Prepare journal changed'};
        if (!fs.unlink(journal_dir + '/' + source + '.prepare.json')) return {ok:false,error:'Cannot clear prepare journal'};
        return {ok:true};
    } catch (e) { return {ok:false,error:'Prepare recovery failed'}; }
}
return { cleanup };
