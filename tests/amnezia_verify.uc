let verifier = require('subscription.amnezia_verify');
function expect(v, m) { if (!v) die(m + '\n'); }
let peer = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=', mode = '', ticks = 0;
function runner(args) {
    let value;
    if (args[0] == 'ubus') value = { up: mode != 'down', l3_device: 'afawg_a', 'ipv4-address': [{address:'10.0.0.2',mask:32}] };
    else if (args[2] == 'awg') return { ok:true, output:peer + '\t' + (mode == 'old' ? '1' : '9990') + '\n' };
    else if (args[6] == 'rule') value = [
        { priority:1000, oif:'afawg_a', table:mode == 'table' ? '222' : '16866' },
        { priority:1001, oif:'afawg_a', action:mode == 'deny' ? 'unreachable' : 'prohibit' }
    ];
    else value = [{ dst:'default', dev:mode == 'route' ? 'wan' : 'afawg_a' }];
    return { ok:true, output:sprintf('%J', value) };
}
function verify() {
    return verifier.verify('afawg_a','16866','1000',['10.0.0.2/32'],peer,true,false,1000,
        runner,function(n) { ticks += n; },function() { return ticks; },function() { return 10000; });
}
expect(verify().ok, 'Ready device was rejected');
for (let test in ['down','table','deny','route','old']) {
    mode = test; ticks = 0;
    let r = verify();
    expect(!r.ok && index(sprintf('%J', r), peer) < 0, 'Invalid state accepted or peer leaked: ' + test);
}
let netifd = require('subscription.amnezia_netifd'), routes = require('subscription.amnezia_routes');
let parsed = { ok:true, interface:{ private_key:'test-secret', addresses:['10.0.0.2/32'] },
    peers:[{ public_key:peer, allowed_ips:['0.0.0.0/0'], endpoint_host:'example.org', endpoint_port:'443' }] };
let p = netifd.prepare(parsed, 'afawg_a'), rp = routes.prepare('afawg_a','16866','1000',true,false);
let sections = {};
function section(typ, options) { let out = { '.type':typ }; for (let k in keys(options)) out[k] = options[k]; return out; }
sections.afawg_a = section('interface', p.iface);
sections.afawg_a_peer = section(p.peer_type, p.peer);
for (let e in rp.entries) sections[e.name] = section(e.type, e.options);
let cursor = { get_all:function(pkg, name) { return sections[name]; } };
expect(verifier.verify_uci(cursor, parsed, 'afawg_a','16866','1000',true,false).ok, 'Matching UCI rejected');
sections.afawg_a.private_key = 'changed-secret';
let bad = verifier.verify_uci(cursor, parsed, 'afawg_a','16866','1000',true,false);
expect(!bad.ok && index(sprintf('%J',bad),'changed-secret') < 0, 'Altered UCI accepted or secret exposed');
print('AmneziaWG live state verifier tests passed\n');
