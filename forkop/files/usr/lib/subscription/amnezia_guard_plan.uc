// Experimental guard-plan contract only. It neither installs a guard nor
// guarantees exclusive mark ownership against other router applications.
// No caller may activate an outbound until the complete rule is installed.
let routes = require('subscription.amnezia_routes');
const AWG_BASE = 0x18000000; // outbound bit 0x08000000 + candidate 0x10000000
function plan(entries, occupied_marks, outbound_mark) {
    if (type(entries) != 'array' || type(occupied_marks) != 'array' ||
        outbound_mark != 0x08000000 || length(entries) > 32)
        return { ok: false, error: 'Invalid guard allocation request' };
    let result = [], names = {}, marks = {};
    for (let entry in entries) {
        if (type(entry) != 'object' || !routes.prepare(entry.name, entry.table, entry.priority, true, false).ok || names[entry.name])
            return { ok: false, error: 'Invalid guard entry' };
        let mark = AWG_BASE | int(entry.table);
        if (marks['' + mark]) return { ok: false, error: 'Duplicate guard mark' };
        for (let used in occupied_marks)
            if (type(used) != 'int' || used == mark) return { ok: false, error: 'Mark collision or invalid allocation' };
        names[entry.name] = true; marks['' + mark] = true;
        push(result, { name: entry.name, table: entry.table, mark });
    }
    return { ok: true, guards: result };
}
return { plan };
