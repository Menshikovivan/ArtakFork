// Apply one NEW AWG interface. This lock coordinates ArtakFork imports only;
// LuCI and other UCI writers do not use it. Network reload is global. Callers
// must also check kernel route/table collisions before invoking this module.
let fs = require('fs');
let uci = require('uci');
let importer = require('subscription.amnezia_import');
let routes = require('subscription.amnezia_routes');
let activation = require('subscription.amnezia_activate');
let runtime_check = require('subscription.amnezia_runtime_check');

function normalized(section) {
    if (type(section) != 'object') return null;
    let out = {};
    for (let k in sort(keys(section)))
        if (substr(k, 0, 1) != '.' || k == '.type') out[k] = section[k];
    return sprintf('%J', out);
}
function apply(text, name, table, priority, timeout_ms, opts) {
    opts = opts || {};
    let config_dir = opts.config_dir || '/etc/config';
    let lock_dir = opts.lock_dir || '/tmp/artak-awg-apply.lock';
    let delta = lock_dir + '/delta';
    // Alternate directories exist only for isolated tests. A caller must never
    // pass paths derived from subscription content or unauthenticated input.
    if (!fs.mkdir(lock_dir)) return { ok: false, error: 'Another import is running or a stale lock exists' };
    let created_delta = false, cursor = null, names = [], snapshots = {}, committed = false;
    function process() {
    try {
        // Standard UCI saved deltas are shared with LuCI and may be applied by
        // network reload. Refuse if present; this does not eliminate races.
        if (config_dir == '/etc/config' && fs.stat('/tmp/.uci/network') != null)
            return { ok: false, error: 'Pending network changes detected; apply or discard them first' };
        let available = runtime_check.check(table, priority, opts.runtime_runner);
        if (!available.ok) return available;
        if (!fs.chmod(lock_dir, 448) || !fs.mkdir(delta))
            return { ok: false, error: 'Could not create private UCI workspace' };
        created_delta = true;
        cursor = uci.cursor(config_dir, delta, '');
        if (!cursor) return { ok: false, error: 'Could not open UCI' };
        let result = importer.stage(cursor, text, name, table, priority);
        if (!result.ok) return result;
        let plan = routes.prepare(name, table, priority, result.ipv4, result.ipv6);
        names = [name, name + '_peer'];
        for (let entry in plan.entries) push(names, entry.name);
        for (let n in names) {
            let value = normalized(cursor.get_all('network', n));
            if (value == null) return { ok: false, error: 'Could not verify staged section' };
            snapshots[n] = value;
        }
        let addresses = cursor.get('network', name, 'addresses');
        if (!importer.commit_staged(cursor).ok)
            return { ok: false, error: 'Commit uncertain; inspect network configuration' };
        committed = true;
        if (config_dir == '/etc/config' && fs.stat('/tmp/.uci/network') != null)
            return { ok: false, error: 'Pending network changes appeared; inspect owned configuration' };
        available = runtime_check.check(table, priority, opts.runtime_runner);
        if (!available.ok) return { ok: false, error: 'Kernel routing changed; inspect owned configuration' };
        let started = activation.start(name, addresses, timeout_ms, opts.runner, opts.pause, opts.now);
        if (started.ok) return { ok: true, name };
        if (!activation.stop(name, opts.runner).ok)
            return { ok: false, error: 'Activation failed; could not stop interface; inspect network configuration' };
        let check = uci.cursor(config_dir, delta, '');
        if (!check || check.load('network') == null)
            return { ok: false, error: 'Activation failed; cannot inspect rollback state' };
        for (let n in names)
            if (normalized(check.get_all('network', n)) != snapshots[n])
                return { ok: false, error: 'Activation failed; owned configuration changed, rollback refused' };
        for (let n in names)
            if (check.delete('network', n) == null)
                return { ok: false, error: 'Activation failed; rollback could not be staged' };
        if (!check.commit('network'))
            return { ok: false, error: 'Activation failed; rollback commit uncertain' };
        if (!activation.reload(opts.runner).ok)
            return { ok: false, error: 'Configuration removed but network reload failed' };
        return { ok: false, error: 'Activation failed; owned configuration removed' };
    }
    catch (e) {
        return { ok: false, error: committed ? 'Apply failed after commit; inspect network configuration' : 'Apply failed before commit' };
    }
    }
    let result = process();
    // UCI delta can contain key material; remove only our fixed path.
    if (created_delta) { fs.unlink(delta + '/network'); fs.rmdir(delta); }
    fs.rmdir(lock_dir);
    return result;
}
return { apply };
