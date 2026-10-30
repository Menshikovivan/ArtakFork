// In-memory bridge from a validated private subscription candidate to netifd
// and routing plans. Never log or serialize the successful result: it contains
// private key material. This function does not stage UCI or activate tunnels.
let store = require('subscription.amnezia_store');
let netifd = require('subscription.amnezia_netifd');
let routes = require('subscription.amnezia_routes');

function prepare(dir, source, identity, allocations) {
    let profiles = store.load(dir, source, identity);
    if (type(profiles) != 'array' || type(allocations) != 'array' ||
        !length(profiles) || length(profiles) != length(allocations))
        return { ok: false, error: 'No current candidate or invalid allocations' };
    let plans = [], names = {}, tables = {}, priorities = {};
    for (let i = 0; i < length(profiles); i++) {
        let allocation = allocations[i];
        if (type(allocation) != 'object') return { ok: false, error: 'Invalid allocation' };
        let network = netifd.prepare(profiles[i], allocation.name);
        if (!network.ok) return { ok: false, error: 'Invalid interface plan' };
        let ipv4 = false, ipv6 = false;
        for (let addr in profiles[i].peers[0].allowed_ips) {
            if (addr == '0.0.0.0/0') ipv4 = true;
            if (addr == '::/0') ipv6 = true;
        }
        let routing = routes.prepare(allocation.name, allocation.table, allocation.priority, ipv4, ipv6);
        if (!routing.ok) return { ok: false, error: 'Invalid route plan' };
        // Each plan owns two adjacent priorities (lookup and prohibit).
        let p = +allocation.priority;
        if (names[allocation.name] || tables[allocation.table] || priorities['' + p] || priorities['' + (p + 1)])
            return { ok: false, error: 'Duplicate or overlapping allocation' };
        names[allocation.name] = true;
        tables[allocation.table] = true;
        priorities['' + p] = true;
        priorities['' + (p + 1)] = true;
        push(plans, { network, routing });
    }
    return { ok: true, plans };
}

return { prepare };
