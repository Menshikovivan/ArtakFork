// Plan and stage private netifd routing sections only. Caller supplies an
// already loaded isolated cursor and verifies kernel state and rollback.
// Bound IPv4 sockets can still use an on-link route after a prohibit error;
// these rules are NOT a kill switch or a substitute for interface lifecycle.
function prepare(name, table, priority, ipv4, ipv6) {
    if (type(name) != 'string' || !match(name, /^afawg_[a-z0-9]{1,8}$/) ||
        type(table) != 'string' || !match(table, /^[0-9]{1,5}$/) ||
        type(priority) != 'string' || !match(priority, /^[0-9]{1,5}$/) ||
        +table < 10000 || +table > 30000 || +priority < 1000 || +priority > 29999 ||
        type(ipv4) != 'boolean' || type(ipv6) != 'boolean' || (!ipv4 && !ipv6))
        return { ok: false, error: 'Invalid private route request' };
    let entries = [];
    for (let family in [4, 6]) {
        if (family == 4 && !ipv4 || family == 6 && !ipv6) continue;
        let suffix = sprintf('%d', family);
        push(entries, { name: name + '_rt' + suffix, type: family == 4 ? 'route' : 'route6',
            options: { interface: name, target: family == 4 ? '0.0.0.0/0' : '::/0', table } });
        push(entries, { name: name + '_rl' + suffix, type: family == 4 ? 'rule' : 'rule6',
            options: { out: name, priority, lookup: table } });
        push(entries, { name: name + '_deny' + suffix, type: family == 4 ? 'rule' : 'rule6',
            options: { out: name, priority: sprintf('%d', +priority + 1), action: 'prohibit' } });
    }
    return { ok: true, entries, table, priority };
}

// Does not load, save, commit or activate anything. Checking UCI alone cannot
// detect runtime iproute rules or named table aliases: caller must check those.
function stage_new(cursor, name, table, priority, ipv4, ipv6) {
    let plan = prepare(name, table, priority, ipv4, ipv6);
    if ((type(cursor) != 'object' && type(cursor) != 'resource') || !plan.ok)
        return { ok: false, error: 'Invalid route stage request' };
    let created = [];
    try {
        if (cursor.get('network', name, 'proto') != 'amneziawg')
            return { ok: false, error: 'Managed interface not staged' };
        for (let entry in plan.entries)
            if (cursor.get('network', entry.name) != null)
                return { ok: false, error: 'Route section name already exists' };
        let collision = false;
        for (let stype in ['route', 'route6', 'rule', 'rule6', 'interface'])
            cursor.foreach('network', stype, function(s) {
                for (let key in ['table', 'lookup', 'ip4table', 'ip6table'])
                    if (s[key] != null && sprintf('%s', s[key]) == table) collision = true;
                if ((stype == 'rule' || stype == 'rule6') && s.priority != null &&
                    (+s.priority == +priority || +s.priority == +priority + 1)) collision = true;
            });
        if (collision) return { ok: false, error: 'Route table or priority already used' };
        for (let entry in plan.entries) {
            push(created, entry.name);
            if (cursor.set('network', entry.name, entry.type) == null) die('set failed');
            for (let key in keys(entry.options))
                if (cursor.set('network', entry.name, key, entry.options[key]) == null) die('set failed');
        }
        return { ok: true, entries: length(plan.entries) };
    }
    catch (e) {
        for (let section in created) try { cursor.delete('network', section); } catch (ignored) {}
        return { ok: false, error: 'Could not stage private routes' };
    }
}
return { prepare, stage_new };
