// Conservative point-in-time audit. Unknown mark expressions fail closed.
// Callers must hold lifecycle locks and recheck immediately before publishing;
// independent external writers can still race after the inspection.
let activation = require('subscription.amnezia_activate');
function number(value) {
    if (type(value) == 'int') return value >= 0 && value <= 0xffffffff ? value : null;
    if (type(value) != 'string') return null;
    let v = null;
    if (match(value, /^0x[0-9a-fA-F]{1,8}$/)) v = int(substr(value, 2), 16);
    else if (match(value, /^[0-9]{1,10}$/)) v = int(value, 10);
    return type(v) == 'int' && v >= 0 && v <= 0xffffffff ? v : null;
}
function has_mark(value) {
    if (type(value) == 'array') { for (let item in value) if (has_mark(item)) return true; }
    if (type(value) == 'object') {
        if (value.meta?.key == 'mark') return true;
        for (let key in keys(value)) if (has_mark(value[key])) return true;
    }
    return false;
}
function read_json(runner, args) {
    let result = runner(args);
    if (type(result) != 'object' || result.ok !== true || type(result.output) != 'string') return null;
    try { return json(result.output); } catch (e) { return null; }
}
function audit(marks, opts) {
    opts = type(opts) == 'object' ? opts : {};
    let runner = type(opts.runner) == 'function' ? opts.runner : activation.run;
    if (type(marks) != 'array' || !length(marks) || length(marks) > 64) return {ok:false,error:'Invalid marks'};
    for (let mark in marks) if (type(mark) != 'int' || mark < 1 || mark > 0xffffffff) return {ok:false,error:'Invalid marks'};
    try {
        for (let family in ['-4', '-6']) {
            let rules = read_json(runner, ['timeout','3','ip','-j','-N',family,'rule','show']);
            if (type(rules) != 'array') return {ok:false,error:'Cannot inspect IP rules'};
            for (let rule in rules) {
                if (type(rule) != 'object') return {ok:false,error:'Unsupported IP rule'};
                if (rule.fwmark == null && rule.fwmask == null) continue;
                if (rule.fwmark == null || rule.not === true || rule.invert === true) return {ok:false,error:'Unsupported IP mark rule'};
                let value = number(rule.fwmark), mask = rule.fwmask == null ? 0xffffffff : number(rule.fwmask);
                if (value == null || mask == null) return {ok:false,error:'Unsupported IP mark rule'};
                for (let mark in marks)
                    if ((mark & mask) == (value & mask)) return {ok:false,error:'IP rule mark conflict'};
            }
        }
        let doc = read_json(runner, ['timeout','3','nft','-j','list','ruleset']);
        if (type(doc?.nftables) != 'array') return {ok:false,error:'Cannot inspect nftables'};
        for (let item in doc.nftables) {
            if (type(item) != 'object') return {ok:false,error:'Unsupported nftables data'};
            if (item.rule == null) continue;
            if (type(item.rule.expr) != 'array') return {ok:false,error:'Unsupported nftables rule'};
            for (let expression in item.rule.expr) {
                if (type(expression) != 'object') return {ok:false,error:'Unsupported nftables expression'};
                let names = keys(expression);
                let understood = ['match','counter','mangle','accept','drop','return','jump','goto','reject','log','limit','quota',
                    'tproxy','dnat','snat','masquerade','redirect','notrack','flow','synproxy','set','map','vmap'];
                if (length(names) != 1 || index(understood, names[0]) < 0)
                    return {ok:false,error:'Unsupported nftables expression'};
                if (expression.mangle != null) {
                    let write = expression.mangle;
                    if (type(write) != 'object' || type(write.key) != 'object') return {ok:false,error:'Unsupported nftables writer'};
                    if (write.key.meta?.key == 'mark') {
                        let value = number(write.value);
                        if (value == null) return {ok:false,error:'Unsupported nft mark writer'};
                        for (let mark in marks) if (mark == value) return {ok:false,error:'nft mark writer conflict'};
                    } else if (has_mark(write.key)) return {ok:false,error:'Unsupported nft mark writer'};
                } else if (expression.match == null && has_mark(expression)) {
                    // Unknown statements involving packet marks may write them.
                    return {ok:false,error:'Unsupported nft mark expression'};
                }
                // Legacy extensions may write marks without exposing an AST.
                if (expression.xt != null) return {ok:false,error:'Unsupported nft extension'};
            }
        }
        return {ok:true};
    } catch (e) { return {ok:false,error:'Cannot audit marks'}; }
}
return { audit };
