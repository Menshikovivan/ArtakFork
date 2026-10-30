// Point-in-time proof of the exact nft guard for a journaled generation swap.
// Callers hold all lifecycle locks. This is not a lifetime guarantee against
// external nft writers and does not install firewall rules.
let snapshot = require('subscription.amnezia_snapshot');
let journal = require('subscription.amnezia_swap_journal');
let generation = require('subscription.amnezia_generation');
let union = require('subscription.amnezia_guard_union');
let activation = require('subscription.amnezia_activate');
let constants = require('core.constants');
function same_journal(a, b) {
    if (type(a) != 'object' || type(b) != 'object') return false;
    for (let k in ['source','old_generation','new_generation','old_snapshot','new_snapshot','phase'])
        if (a[k] != b[k]) return false;
    return true;
}
function record_matches(snap, record, source) {
    if (type(snap) != 'object' || type(snap.entries) != 'array' || type(record) != 'object' ||
        record.source != source || type(record.entries) != 'array' || !length(record.entries)) return false;
    let matches = 0;
    for (let item in snap.entries) {
        if (item.source != source) continue;
        let found = false;
        for (let entry in record.entries)
            if (item.index == entry.index && item.name == entry.name && item.table == entry.table &&
                item.priority == entry.priority && item.identity == record.identity && item.revision == record.revision)
                found = true;
        if (!found) return false;
        matches++;
    }
    return matches == length(record.entries);
}
function parse_rule(rule) {
    if (type(rule) != 'object' || type(rule.expr) != 'array' || length(rule.expr) != 4) return null;
    let a = rule.expr[0]?.match, b = rule.expr[1]?.match;
    if (a?.op != '==' || a?.left?.meta?.key != 'mark' || b?.op != '!=' || b?.left?.meta?.key != 'oifname' ||
        !exists(rule.expr[2], 'counter') || !exists(rule.expr[3], 'drop') || type(b.right) != 'string') return null;
    return { mark:int(a.right), name:b.right };
}
function verify(journal_dir, generation_dir, source, old_dir, new_dir, opts) {
    opts = type(opts) == 'object' ? opts : {};
    let read_journal = opts.read_journal || journal.read, read_snapshot = opts.load || snapshot.load;
    let read_generation = opts.read_generation || generation.read_generation, current_id = opts.current_id || generation.current_id;
    let runner = opts.runner || activation.run, table = opts.table || constants.NFT_TABLE_NAME || 'ForkopTable';
    if (type(table) != 'string' || !match(table, /^[A-Za-z0-9_]{1,64}$/)) return {ok:false,error:'Invalid guard table'};
    try {
        let j = read_journal(journal_dir, source);
        if (type(j) != 'object' || j.source != source || index(['union','published','verified'], j.phase) < 0 ||
            type(j.old_snapshot) != 'string' || !match(j.old_snapshot, /^[0-9a-f]{64}$/) ||
            type(j.new_snapshot) != 'string' || !match(j.new_snapshot, /^[0-9a-f]{64}$/))
            return {ok:false,error:'Invalid swap journal'};
        let pointer = current_id(generation_dir, source);
        if (pointer != (j.phase == 'union' ? j.old_generation : j.new_generation))
            return {ok:false,error:'Generation pointer differs from journal'};
        let old = read_snapshot(old_dir), next = read_snapshot(new_dir);
        if (old?.revision != j.old_snapshot || next?.revision != j.new_snapshot ||
            !record_matches(old, read_generation(generation_dir, source, j.old_generation), source) ||
            !record_matches(next, read_generation(generation_dir, source, j.new_generation), source))
            return {ok:false,error:'Snapshots do not match journal generations'};
        let plan = union.plan(old.entries, next.entries, []);
        if (!plan.ok || !length(plan.guards)) return {ok:false,error:'Invalid union plan'};
        let response = runner(['timeout','3','nft','-j','list','chain','inet',table,'mangle_output']), data = null;
        if (response.ok) try { data = json(response.output); } catch (ignored) {}
        if (type(data?.nftables) != 'array') return {ok:false,error:'Cannot inspect guard'};
        let chain = null, rules = [];
        for (let item in data.nftables) {
            if (item.chain?.name == 'mangle_output' && item.chain.table == table && item.chain.family == 'inet') chain = item.chain;
            if (item.rule?.chain == 'mangle_output' && item.rule.table == table && item.rule.family == 'inet') push(rules, item.rule);
        }
        if (chain?.type != 'route' || chain?.hook != 'output' || chain?.prio != -150 || chain?.policy != 'accept' || length(rules) < length(plan.guards))
            return {ok:false,error:'Guard chain differs'};
        let seen = {};
        for (let i = 0; i < length(plan.guards); i++) {
            let parsed = parse_rule(rules[i]), matched = false;
            if (parsed == null) return {ok:false,error:'Guard rule missing or reordered'};
            for (let g in plan.guards)
                if (g.name == parsed.name && g.mark == parsed.mark && !seen[g.name]) { seen[g.name] = true; matched = true; }
            if (!matched) return {ok:false,error:'Guard rule differs'};
        }
        let old_after = read_snapshot(old_dir), next_after = read_snapshot(new_dir);
        if (old_after?.revision != j.old_snapshot || next_after?.revision != j.new_snapshot ||
            !same_journal(j, read_journal(journal_dir, source)) || current_id(generation_dir, source) != pointer)
            return {ok:false,error:'Swap state changed during verification'};
        return {ok:true, guards:plan.guards};
    } catch (e) { return {ok:false,error:'Cannot verify union guard'}; }
}
return { verify };
