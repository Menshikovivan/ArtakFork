// Inspect real kernel policy state with iproute2 JSON and numeric table names.
// This detects current conflicts only; other writers can race the check.
let activation = require('subscription.amnezia_activate');
function check(table, priority, runner) {
    if (type(table) != 'string' || !match(table, /^[0-9]{1,5}$/) ||
        type(priority) != 'string' || !match(priority, /^[0-9]{1,5}$/) ||
        int(table) < 10000 || int(table) > 30000 || int(priority) < 1000 || int(priority) > 29999)
        return { ok: false, error: 'Invalid allocation' };
    runner = runner || activation.run;
    for (let family in ['-4', '-6']) {
        for (let object in ['rule', 'route']) {
            let args = object == 'route' ? ['ip', '-j', '-N', family, 'route', 'show', 'table', 'all'] :
                ['ip', '-j', '-N', family, 'rule', 'show'];
            let reply = runner(args), records = null;
            if (reply.ok) try { records = json(reply.output); } catch (ignored) {}
            if (type(records) != 'array') return { ok: false, error: 'Cannot inspect kernel routing state; iproute2 JSON is required' };
            for (let item in records) {
                if (type(item) != 'object') return { ok: false, error: 'Invalid kernel routing response' };
                if (item.table != null) {
                    let t = '' + item.table;
                    if (!match(t, /^[0-9]+$/)) return { ok: false, error: 'Non-numeric kernel routing table' };
                    if (int(t) == int(table)) return { ok: false, error: 'Kernel routing table already used' };
                }
                if (object == 'rule' && item.priority != null) {
                    let p = '' + item.priority;
                    if (!match(p, /^[0-9]+$/)) return { ok: false, error: 'Invalid kernel rule priority' };
                    if (int(p) == int(priority) || int(p) == int(priority) + 1)
                        return { ok: false, error: 'Kernel rule priority already used' };
                }
            }
        }
    }
    return { ok: true };
}
return { check };
