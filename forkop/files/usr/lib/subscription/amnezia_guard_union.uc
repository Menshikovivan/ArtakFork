// Compute the simultaneous guard for old and new generations. This is only a
// plan: it does not install nft rules, detect masked mark collisions, or make
// the transition atomic. The lifecycle must validate those separately.
let guard = require('subscription.amnezia_guard_plan');
function plan(old_entries, new_entries, occupied_marks) {
    if (type(old_entries) != 'array' || type(new_entries) != 'array' || type(occupied_marks) != 'array')
        return { ok:false, error:'Invalid guard union' };
    let entries = [], by_name = {}, by_table = {}, priorities = {};
    for (let group in [old_entries, new_entries]) {
        for (let item in group) {
            if (type(item) != 'object' || type(item.name) != 'string' || type(item.table) != 'string' || type(item.priority) != 'string')
                return { ok:false, error:'Invalid guard entry' };
            let previous = by_name[item.name];
            if (previous != null) {
                if (previous.table != item.table || previous.priority != item.priority)
                    return { ok:false, error:'Interface changed allocation' };
                continue;
            }
            if (by_table[item.table]) return { ok:false, error:'Guard table collision' };
            let priority = int(item.priority);
            if (priorities['' + priority] || priorities['' + (priority + 1)])
                return { ok:false, error:'Guard priority collision' };
            let entry = { name:item.name, table:item.table, priority:item.priority };
            by_name[item.name] = entry; by_table[item.table] = true;
            priorities['' + priority] = true; priorities['' + (priority + 1)] = true;
            push(entries, entry);
        }
    }
    if (length(entries) > 32) return { ok:false, error:'Guard union is too large' };
    return guard.plan(entries, occupied_marks, 0x08000000);
}
return { plan };
