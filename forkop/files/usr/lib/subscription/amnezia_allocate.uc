// Select one unused allocation. This does not reserve it: callers must hold
// lifecycle locks and repeat checks immediately before committing or starting.
// Other UCI/kernel writers do not honor our lock; this cannot exclude races or
// detect conflicts caused by unrelated policy-rule mark masks.
let runtime = require('subscription.amnezia_runtime_check');
let activation = require('subscription.amnezia_activate');
function choose(cursor, opts) {
    opts = type(opts) == 'object' ? opts : {};
    if ((type(cursor) != 'object' && type(cursor) != 'resource'))
        return { ok: false, error: 'Cannot inspect UCI network' };
    let runner = type(opts.runner) == 'function' ? opts.runner : activation.run;
    let check = type(opts.check) == 'function' ? opts.check : runtime.check;
    try {
        if (cursor.load('network') == null) return { ok: false, error: 'Cannot inspect UCI network' };
        let response = runner(['ip', '-j', 'link', 'show']), links = null;
        if (type(response) == 'object' && response.ok) try { links = json(response.output); } catch (e) {}
        if (type(links) != 'array') return { ok: false, error: 'Cannot inspect kernel interfaces' };
        let used_names = {};
        for (let item in links) {
            if (type(item) != 'object' || type(item.ifname) != 'string')
                return { ok: false, error: 'Invalid kernel interface response' };
            used_names[item.ifname] = true;
        }
        let tables = {}, priorities = {};
        for (let section_type in ['route', 'route6', 'rule', 'rule6', 'interface'])
            cursor.foreach('network', section_type, function(section) {
                for (let key in ['table', 'lookup', 'ip4table', 'ip6table'])
                    if (section[key] != null) tables['' + section[key]] = true;
                if ((section_type == 'rule' || section_type == 'rule6') && section.priority != null)
                    priorities['' + section.priority] = true;
            });
        for (let i = 1; i <= 32; i++) {
            let name = sprintf('afawg_%d', i), table = sprintf('%d', 15000 + i), priority = sprintf('%d', 16000 + 2 * i);
            if (used_names[name] || tables[table] || priorities[priority] || priorities['' + (+priority + 1)]) continue;
            let occupied = false;
            for (let suffix in ['', '_peer', '_rt4', '_rl4', '_deny4', '_rt6', '_rl6', '_deny6'])
                if (cursor.get('network', name + suffix) != null) occupied = true;
            if (occupied) continue;
            let current = check(table, priority, runner);
            if (type(current) != 'object') return { ok: false, error: 'Cannot inspect kernel routing' };
            if (current.ok === true) return { ok: true, name, table, priority };
            if (current.error == 'Kernel routing table already used' || current.error == 'Kernel rule priority already used') continue;
            return { ok: false, error: 'Cannot inspect kernel routing' };
        }
        return { ok: false, error: 'No unused allocation' };
    } catch (e) { return { ok: false, error: 'Cannot inspect allocation' }; }
}
return { choose };
