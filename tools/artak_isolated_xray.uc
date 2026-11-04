#!/usr/bin/env ucode
// Transform a protected generated configuration for a local SOCKS-only probe.
// This deliberately does not modify the source or any OpenWrt service.
let fs = require('fs');
let source = ARGV[0], output = ARGV[1], port = int(ARGV[2]);
let logpath = ARGV[3], negative = ARGV[4] == 'negative';
let text = fs.readfile(source);
let c = text == null ? null : json(text);
if (type(c) != 'object' || type(c.routing) != 'object' ||
    type(c.routing.rules) != 'array' || type(c.outbounds) != 'array' ||
    c.reverse != null || port < 1024 || port > 65535)
    exit(1);

let tag = 'artak-isolated-test', blocked = 'artak-isolated-block';
for (let o in c.outbounds)
    if (o.tag == blocked)
        exit(1);
let rules = [];
let changed = 0;
for (let r in c.routing.rules) {
    if (type(r) != 'object')
        exit(1);
    if (type(r.inboundTag) == 'array') {
        let tags = [];
        for (let t in r.inboundTag) {
            if (t == 'tproxy-in' || t == 'tproxy6-in' ||
                t == 'tproxy-fakeip-in' || t == 'tproxy-fakeip6-in') {
                if (index(tags, tag) < 0) push(tags, tag);
                changed++;
            }
            else push(tags, t);
        }
        r.inboundTag = tags;
    }
    push(rules, r);
}
if (!changed) exit(1);
if (negative) {
    push(c.outbounds, { tag: blocked, protocol: 'blackhole' });
    let prefixed = [{ type: 'field', inboundTag: [tag], outboundTag: blocked }];
    for (let rule in rules) push(prefixed, rule);
    rules = prefixed;
}
c.inbounds = [{ tag, listen: '127.0.0.1', port, protocol: 'socks',
    settings: { auth: 'noauth', udp: false } }];
c.routing.rules = rules;
c.log = { access: logpath, error: 'none', loglevel: 'warning' };
if (fs.writefile(output, sprintf('%J\n', c)) == null) exit(1);
