// Experimental single-file import. Never pass caller-controlled options,
// route allocations, or secrets to a shell command or return them to LuCI.
let parser = require('subscription.amnezia_conf');
function apply(config, deps) {
    if (type(config) != 'string' || length(config) > 65536 || !parser.parse_conf(config).ok)
        return { ok: false, error: 'Invalid configuration' };
    try {
        let cursor = deps.cursor();
        if (!cursor || cursor.load('network') == null)
            return { ok: false, error: 'Unable to inspect network configuration' };
        for (let i = 1; i <= 32; i++) {
            let name = sprintf('afawg_%d', i), table = sprintf('%d', 15000 + i), priority = sprintf('%d', 16000 + 2 * i);
            if (cursor.get('network', name) != null || cursor.get('network', name + '_peer') != null) continue;
            if (!deps.check(table, priority).ok) continue;
            // The apply implementation repeats collision and pending checks.
            let result = deps.apply(config, name, table, priority, 5000);
            if (type(result) == 'object' && result.ok === true)
                return { ok: true, name };
            // Do not echo backend error/exception text: it could include input.
            return { ok: false, error: 'Import failed; inspect network configuration before retrying' };
        }
        return { ok: false, error: 'No available interface or routing allocation' };
    } catch (e) {
        return { ok: false, error: 'Import failed; inspect network configuration before retrying' };
    }
}
return { apply };
