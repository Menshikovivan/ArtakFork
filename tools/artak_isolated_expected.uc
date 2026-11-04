#!/usr/bin/env ucode
// Select an expected Xray outbound from explicit domain rules only. Ambiguous
// conditions are rejected rather than guessing the route used by a client.
let fs = require('fs');
let input = ARGV[0], host = lc(ARGV[1] || ''), output = ARGV[2];
let text = fs.readfile(input), c = text == null ? null : json(text);
if (host == '' || type(c) != 'object' || type(c.routing) != 'object' ||
    type(c.routing.rules) != 'array' || type(c.outbounds) != 'array') exit(1);
let chosen = null;
for (let r in c.routing.rules) {
    if (type(r) != 'object') exit(1);
    let target = r.inboundTag == null;
    if (r.inboundTag != null && type(r.inboundTag) != 'array') exit(1);
    for (let t in r.inboundTag || [])
        if (t == 'tproxy-in' || t == 'tproxy6-in' ||
            t == 'tproxy-fakeip-in' || t == 'tproxy-fakeip6-in') target = true;
    if (!target) continue;
    for (let key in keys(r))
        if (key != 'type' && key != 'inboundTag' && key != 'domain' &&
            key != 'ip' && key != 'outboundTag' && key != 'balancerTag') exit(1);
    if (r.type != null && r.type != 'field') exit(1);
    if (r.source != null || r.sourcePort != null || r.user != null ||
        r.network != null || r.port != null || r.protocol != null ||
        r.attrs != null || r.process != null) exit(1);
    if (type(r.domain) != 'array') {
        if (r.ip != null && c.routing.domainStrategy != 'IPOnDemand') continue;
        exit(1);
    }
    let match_found = false, ambiguous = false;
    for (let item in r.domain) {
        if (type(item) != 'string' || item == '') { ambiguous = true; continue; }
        item = lc(item);
        if (index(item, 'full:') == 0) {
            if (length(item) == 5) { ambiguous = true; continue; }
            if (host == substr(item, 5)) match_found = true;
        }
        else if (index(item, 'domain:') == 0) {
            let suffix = substr(item, 7);
            if (suffix == '') { ambiguous = true; continue; }
            if (host == suffix || (length(host) > length(suffix) &&
                substr(host, length(host) - length(suffix) - 1) == '.' + suffix)) match_found = true;
        }
        else if (index(item, ':') >= 0) ambiguous = true;
        else if (index(host, item) >= 0) match_found = true;
    }
    if (!match_found) { if (ambiguous) exit(1); continue; }
    if (r.ip != null) exit(1);
    chosen = r;
    break;
}
if (chosen == null) exit(1);
let allowed = [];
if (type(chosen.outboundTag) == 'string' && chosen.outboundTag != '')
    push(allowed, chosen.outboundTag);
else if (type(chosen.balancerTag) == 'string' && type(c.routing.balancers) == 'array') {
    let selectors = null;
    for (let b in c.routing.balancers)
        if (b.tag == chosen.balancerTag) selectors = b.selector;
    if (type(selectors) != 'array' || length(selectors) == 0) exit(1);
    for (let o in c.outbounds)
        for (let selector in selectors)
            if (type(o.tag) == 'string' && type(selector) == 'string' &&
                selector != '' && index(o.tag, selector) == 0 && index(allowed, o.tag) < 0)
                push(allowed, o.tag);
}
if (length(allowed) == 0 || fs.writefile(output, sprintf('%J\n', allowed)) == null) exit(1);
