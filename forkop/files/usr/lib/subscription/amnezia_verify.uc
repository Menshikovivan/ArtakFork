// Point-in-time verifier for a previously created interface. Data is accepted
// only from trusted in-memory config; no keys are passed in argv or output.
let activation = require('subscription.amnezia_activate');
let handshake = require('subscription.amnezia_handshake');
let routes = require('subscription.amnezia_routes');
let netifd = require('subscription.amnezia_netifd');
function same_section(actual, section_type, expected) {
    if (type(actual) != 'object' || actual['.type'] != section_type) return false;
    for (let k in keys(expected))
        if (sprintf('%J', actual[k]) != sprintf('%J', expected[k])) return false;
    for (let k in keys(actual))
        if (substr(k, 0, 1) != '.' && expected[k] == null) return false;
    return true;
}
// Cursor must already be loaded; callers supply parsed config in memory only.
function verify_uci(cursor, parsed, name, table, priority, ipv4, ipv6) {
    let p = netifd.prepare(parsed, name), r = routes.prepare(name, table, priority, ipv4, ipv6);
    if (!p.ok || !r.ok) return { ok: false, error: 'Invalid expected configuration' };
    try {
        if (!same_section(cursor.get_all('network', name), 'interface', p.iface) ||
            !same_section(cursor.get_all('network', p.peer_name), p.peer_type, p.peer))
            return { ok: false, error: 'Managed interface configuration differs' };
        for (let entry in r.entries)
            if (!same_section(cursor.get_all('network', entry.name), entry.type, entry.options))
                return { ok: false, error: 'Managed routing configuration differs' };
        return { ok: true };
    } catch (e) { return { ok: false, error: 'Cannot inspect managed configuration' }; }
}
function read_json(runner, args) {
    let r = runner(args), v = null;
    if (r.ok) try { v = json(r.output); } catch (ignored) {}
    return v;
}
function verify(name, table, priority, addresses, peer, ipv4, ipv6, timeout_ms, runner, pause, now, wall) {
    if (!routes.prepare(name, table, priority, ipv4, ipv6).ok || type(addresses) != 'array' || !length(addresses))
        return { ok: false, error: 'Invalid verification request' };
    runner = runner || activation.run;
    let status = read_json(runner, ['ubus', '-t', '3', 'call', 'network.interface.' + name, 'status', '{}']);
    if (!activation.ready(status, name, addresses)) return { ok: false, error: 'AWG interface is not ready' };
    for (let family in ['-4', '-6']) {
        if (family == '-4' && !ipv4 || family == '-6' && !ipv6) continue;
        let rules = read_json(runner, ['timeout', '3', 'ip', '-j', '-N', family, 'rule', 'show']);
        let entries = read_json(runner, ['timeout', '3', 'ip', '-j', '-N', family, 'route', 'show', 'table', table]);
        if (type(rules) != 'array' || type(entries) != 'array') return { ok: false, error: 'Cannot inspect AWG routing' };
        let lookup = false, deny = false, route = false;
        for (let r in rules) {
            if (type(r) != 'object' || r.oif != name) continue;
            if (int(r.priority) == int(priority) && '' + r.table == table) lookup = true;
            // ip -N emits the kernel FR_ACT_PROHIBIT value as "8" on
            // OpenWrt; non-numeric output may spell it as "prohibit".
            if (int(r.priority) == int(priority) + 1 &&
                (r.action == 'prohibit' || r.action == '8' || r.action == 8)) deny = true;
        }
        for (let r in entries)
            if (type(r) == 'object' && r.dst == 'default' && r.dev == name && (r.table == null || '' + r.table == table)) route = true;
        if (!lookup || !deny || !route) return { ok: false, error: 'AWG route or policy rule missing' };
    }
    return handshake.verify(name, peer, timeout_ms, runner, pause, now, wall).ok ?
        { ok: true, name, table, priority } : { ok: false, error: 'AWG handshake unavailable' };
}
return { verify, verify_uci };
