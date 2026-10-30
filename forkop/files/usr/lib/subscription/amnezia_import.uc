// Restricted one-shot import. It only creates new owned UCI sections, never
// activates netifd, and never returns or logs key material. The caller must
// serialize access to network configuration, verify runtime table/priority
// availability, and supply a fresh isolated UCI cursor. Those preconditions
// are not enforced by UCI itself; do not expose this directly as a UI action.
let conf = require('subscription.amnezia_conf');
let netifd = require('subscription.amnezia_netifd');
let routes = require('subscription.amnezia_routes');

function stage(cursor, text, name, table, priority) {
    if (type(text) != 'string' || length(text) > 65536)
        return { ok: false, error: 'Invalid configuration input' };
    let parsed = conf.parse_conf(text);
    if (!parsed.ok) return { ok: false, error: 'Invalid AmneziaWG configuration' };
    // Only advertise a default route for a family fully covered by AllowedIPs.
    let ipv4 = false, ipv6 = false;
    for (let address in parsed.peers[0].allowed_ips) {
        if (address == '0.0.0.0/0') ipv4 = true;
        if (address == '::/0') ipv6 = true;
    }
    if (!ipv4 && !ipv6) return { ok: false, error: 'A default AllowedIPs route is required' };
    let plan = routes.prepare(name, table, priority, ipv4, ipv6);
    if (!plan.ok) return { ok: false, error: 'Invalid route allocation' };
    // stage_new loads network, so no other pending changes may be on cursor.
    let iface = netifd.stage_new(cursor, parsed, name);
    if (!iface.ok) return { ok: false, error: iface.error };
    let staged = routes.stage_new(cursor, name, table, priority, ipv4, ipv6);
    if (!staged.ok) {
        try { cursor.delete('network', name + '_peer'); } catch (ignored) {}
        try { cursor.delete('network', name); } catch (ignored) {}
        return { ok: false, error: staged.error };
    }
    return { ok: true, name, ipv4, ipv6 };
}

// Commit uncertainty must be handled by inspecting the live owned sections;
// never restore a full old network file over concurrent changes.
function commit_staged(cursor) {
    try {
        if (!cursor.commit('network')) return { ok: false, error: 'Commit failed; state must be inspected' };
        return { ok: true };
    } catch (e) {
        return { ok: false, error: 'Commit failed; state must be inspected' };
    }
}
return { stage, commit_staged };
