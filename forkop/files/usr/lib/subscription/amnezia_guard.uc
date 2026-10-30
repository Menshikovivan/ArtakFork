// Verify the currently installed guard. This is a snapshot only; external nft
// flush/reload can remove it after verification. Do not treat it as a lifetime
// guarantee, and do not enable AWG until reload lifecycle is controlled.
let snapshot = require('subscription.amnezia_snapshot');
let activation = require('subscription.amnezia_activate');
let constants = require('core.constants');
function equal_entry(a, b) {
    for (let key in ['index','name','table','priority','mark','source','identity','revision'])
        if (a[key] != b[key]) return false;
    return true;
}
function parse_rule(rule) {
    if (type(rule) != 'object' || type(rule.expr) != 'array' || length(rule.expr) != 4) return null;
    let a = rule.expr[0]?.match, b = rule.expr[1]?.match;
    if (a?.op != '==' || a?.left?.meta?.key != 'mark' || b?.op != '!=' || b?.left?.meta?.key != 'oifname' ||
        !exists(rule.expr[2], 'counter') || !exists(rule.expr[3], 'drop') || type(b.right) != 'string') return null;
    return { mark: int(a.right), name: b.right };
}
function verify(selected, revision, opts) {
    opts = opts || {};
    let dir = opts.snapshot_dir || getenv('FORKOP_AWG_SNAPSHOT_DIR') || '/etc/forkop/awg-snapshot';
    let table = opts.table || constants.NFT_TABLE_NAME || 'ForkopTable';
    if (type(table) != 'string' || !match(table, /^[A-Za-z0-9_]{1,64}$/) || type(selected) != 'array' ||
        !length(selected) || type(revision) != 'string' || !match(revision, /^[0-9a-f]{64}$/))
        return { ok:false, error:'Invalid guard verification request' };
    let read_snapshot = opts.load || snapshot.load, runner = opts.runner || activation.run;
    let current = read_snapshot(dir);
    if (type(current) != 'object' || current.revision != revision || type(current.entries) != 'array')
        return { ok:false, error:'AWG snapshot changed' };
    let r = runner(['timeout','3','nft','-j','list','chain','inet',table,'mangle_output']);
    let data = null;
    if (r.ok) try { data = json(r.output); } catch (ignored) {}
    if (type(data?.nftables) != 'array') return { ok:false, error:'Cannot inspect AWG guard' };
    let chain = null, rules = [];
    for (let e in data.nftables) {
        if (e.chain != null && e.chain.name == 'mangle_output' && e.chain.table == table && e.chain.family == 'inet') chain = e.chain;
        if (e.rule != null && e.rule.chain == 'mangle_output' && e.rule.table == table && e.rule.family == 'inet') push(rules, e.rule);
    }
    if (chain?.type != 'route' || chain?.hook != 'output' || chain?.prio != -150 || chain?.policy != 'accept' || length(rules) < length(current.entries))
        return { ok:false, error:'AWG guard chain differs' };
    let seen = {};
    for (let i = 0; i < length(current.entries); i++) {
        let g = parse_rule(rules[i]), found = false;
        if (g == null) return { ok:false, error:'AWG guard rule missing or reordered' };
        for (let e in current.entries)
            if (e.mark == g.mark && e.name == g.name && !seen[e.name]) { seen[e.name] = true; found = true; }
        if (!found) return { ok:false, error:'AWG guard rule differs' };
    }
    for (let e in selected) {
        let found = false;
        for (let item in current.entries) if (equal_entry(e, item)) found = true;
        if (!found || !seen[e.name]) return { ok:false, error:'AWG guard does not match snapshot' };
    }
    let after = read_snapshot(dir);
    if (after == null || after.revision != revision) return { ok:false, error:'AWG snapshot changed' };
    return { ok:true, entries:selected };
}
return { verify };
