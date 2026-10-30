// Internal single-candidate bridge. It neither reads subscriptions from the
// network nor publishes an outbound. Callers must hold subscription/reload
// locks, verify the source is still current, reserve names/tables/priorities,
// and apply sing-box separately. The runtime apply module's existing global
// reload and concurrent-UCI-writer limitations continue to apply here.
let store = require('subscription.amnezia_store');
let conf = require('subscription.amnezia_conf');
let netifd = require('subscription.amnezia_netifd');
let routes = require('subscription.amnezia_routes');

function apply_one(dir, source, identity, index, allocation, timeout_ms, opts) {
    let configs = store.load_configs(dir, source, identity);
    if (type(configs) != 'array' || type(index) != 'int' || index < 0 || index >= length(configs) ||
        type(allocation) != 'object')
        return { ok: false, error: 'No current candidate or invalid selection' };
    let parsed = conf.parse_conf(configs[index]);
    if (!parsed.ok || !netifd.prepare(parsed, allocation.name).ok)
        return { ok: false, error: 'Invalid candidate configuration' };
    let ipv4 = false, ipv6 = false;
    for (let ip in parsed.peers[0].allowed_ips) {
        if (ip == '0.0.0.0/0') ipv4 = true;
        if (ip == '::/0') ipv6 = true;
    }
    if (!routes.prepare(allocation.name, allocation.table, allocation.priority, ipv4, ipv6).ok)
        return { ok: false, error: 'Invalid candidate route allocation' };
    opts = type(opts) == 'object' ? opts : {};
    // Tests may inject an in-memory driver; normal callers use the real module.
    let driver = type(opts.apply_driver) == 'function' ? opts.apply_driver : require('subscription.amnezia_apply').apply;
    let result;
    try { result = driver(configs[index], allocation.name, allocation.table, allocation.priority, timeout_ms, opts); }
    catch (e) { return { ok: false, error: 'AWG apply failed; inspect owned configuration' }; }
    if (type(result) != 'object' || result.ok !== true)
        return { ok: false, error: 'AWG apply failed; inspect owned configuration' };
    return { ok: true, name: allocation.name };
}

// An applied interface becomes discoverable only after the caller's verifier
// confirms live state and a private manifest is written. This handles a single
// selected profile. If manifest publication fails after apply, callers must
// inspect and remove the new owned interface; no successful result is returned.
function apply_one_and_record(dir, source, identity, index, allocation, timeout_ms, opts, manifest) {
    if (type(manifest) != 'object' || type(manifest.dir) != 'string' ||
        type(manifest.revision) != 'string' || !match(manifest.revision, /^[0-9a-f]{64}$/) ||
        type(manifest.verify) != 'function')
        return { ok: false, error: 'Active mapping verification is required' };
    let result = apply_one(dir, source, identity, index, allocation, timeout_ms, opts);
    if (!result.ok) return result;
    let active = require('subscription.amnezia_active');
    let entries = [{ index, name: allocation.name, table: allocation.table, priority: allocation.priority }];
    if (!active.save(manifest.dir, source, identity, manifest.revision, entries, manifest.verify))
        return { ok: false, error: 'Interface applied but active mapping failed; cleanup required', name: allocation.name, cleanup_required: true };
    return { ok: true, name: allocation.name };
}
return { apply_one, apply_one_and_record };
