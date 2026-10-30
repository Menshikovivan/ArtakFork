// Internal single-candidate bridge. It neither reads subscriptions from the
// network nor publishes an outbound. Callers must hold subscription/reload
// locks, verify the source is still current, reserve names/tables/priorities,
// and apply sing-box separately. The runtime apply module's existing global
// reload and concurrent-UCI-writer limitations continue to apply here.
let store = require('subscription.amnezia_store');
let conf = require('subscription.amnezia_conf');
let netifd = require('subscription.amnezia_netifd');
let routes = require('subscription.amnezia_routes');
let fs = require('fs');

function apply_loaded(text, allocation, timeout_ms, opts) {
    if (type(text) != 'string' || type(allocation) != 'object')
        return { ok: false, error: 'No current candidate or invalid selection' };
    let parsed = conf.parse_conf(text);
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
    try { result = driver(text, allocation.name, allocation.table, allocation.priority, timeout_ms, opts); }
    catch (e) { return { ok: false, error: 'AWG apply failed; inspect owned configuration' }; }
    if (type(result) != 'object' || result.ok !== true)
        return { ok: false, error: 'AWG apply failed; inspect owned configuration' };
    return { ok: true, name: allocation.name };
}
function apply_one(dir, source, identity, index, allocation, timeout_ms, opts) {
    let configs = store.load_configs(dir, source, identity);
    if (type(configs) != 'array' || type(index) != 'int' || index < 0 || index >= length(configs))
        return { ok: false, error: 'No current candidate or invalid selection' };
    return apply_loaded(configs[index], allocation, timeout_ms, opts);
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
    if (store.revision(dir, source, identity) != manifest.revision)
        return { ok: false, error: 'Candidate revision changed' };
    let configs = store.load_configs(dir, source, identity);
    if (type(configs) != 'array' || type(index) != 'int' || index < 0 || index >= length(configs))
        return { ok: false, error: 'No current candidate or invalid selection' };
    if (store.revision(dir, source, identity) != manifest.revision)
        return { ok: false, error: 'Candidate revision changed' };
    opts = type(opts) == 'object' ? opts : {};
    let cleanup = function() {
        try {
            let driver = type(opts.cleanup_driver) == 'function' ? opts.cleanup_driver : require('subscription.amnezia_apply').cleanup;
            let result = driver(configs[index], allocation.name, allocation.table, allocation.priority, opts);
            return type(result) == 'object' && result.ok === true;
        } catch (e) { return false; }
    };
    let result = apply_loaded(configs[index], allocation, timeout_ms, opts);
    if (!result.ok) return result;
    if (store.revision(dir, source, identity) != manifest.revision)
        return { ok: false, error: 'Candidate changed after apply', name: allocation.name, cleanup_required: !cleanup() };
    if (manifest.last_good_dir != null && !store.promote(dir, manifest.last_good_dir, source, identity, manifest.revision))
        return { ok: false, error: 'Cannot preserve verified candidate', name: allocation.name, cleanup_required: !cleanup() };
    let active = require('subscription.amnezia_active');
    let entries = [{ index, name: allocation.name, table: allocation.table, priority: allocation.priority }];
    if (!active.save(manifest.dir, source, identity, manifest.revision, entries, manifest.verify))
        return { ok: false, error: 'Interface applied but active mapping failed', name: allocation.name, cleanup_required: !cleanup() };
    return { ok: true, name: allocation.name };
}

// Applies one fresh candidate, validates the actual committed UCI and live
// handshake/routes, then records it. Caller owns allocation and lifecycle locks.
// Replacing an existing interface or applying a batch requires another API.
function activate(dir, active_dir, source, identity, index, allocation, timeout_ms, opts) {
    opts = type(opts) == 'object' ? opts : {};
    let revision = store.revision(dir, source, identity);
    let configs = store.load_configs(dir, source, identity);
    if (revision == null || type(configs) != 'array' || type(index) != 'int' || index < 0 || index >= length(configs))
        return { ok: false, error: 'No current candidate or invalid selection' };
    if (type(active_dir) != 'string' || active_dir == '' || active_dir == '/' ||
        fs.stat(active_dir + '/' + source + '.json') != null)
        return { ok: false, error: 'Active source already exists or invalid active directory' };
    let parsed = conf.parse_conf(configs[index]);
    if (!parsed.ok || length(parsed.peers) != 1) return { ok: false, error: 'Invalid candidate' };
    let ipv4 = false, ipv6 = false;
    for (let ip in parsed.peers[0].allowed_ips) {
        if (ip == '0.0.0.0/0') ipv4 = true;
        if (ip == '::/0') ipv6 = true;
    }
    let verify = function(entry) {
        let cursor = opts.cursor || require('uci').cursor();
        if (!cursor || cursor.load('network') == null) return false;
        let module = require('subscription.amnezia_verify');
        let uci_check = type(opts.uci_check) == 'function' ? opts.uci_check : module.verify_uci;
        let live_check = type(opts.live_check) == 'function' ? opts.live_check : module.verify;
        let u = uci_check(cursor, parsed, entry.name, entry.table, entry.priority, ipv4, ipv6);
        if (type(u) != 'object' || u.ok !== true) return false;
        let live = live_check(entry.name, entry.table, entry.priority, parsed.interface.addresses,
            parsed.peers[0].public_key, ipv4, ipv6, timeout_ms);
        return type(live) == 'object' && live.ok === true;
    };
    return apply_one_and_record(dir, source, identity, index, allocation, timeout_ms, opts,
        { dir: active_dir, revision, verify, last_good_dir: opts.last_good_dir || '/etc/forkop/awg-last-good' });
}

function allocate_and_activate(dir, active_dir, source, identity, index, timeout_ms, opts) {
    opts = type(opts) == 'object' ? opts : {};
    let with_lock = type(opts.with_lock) == 'function' ? opts.with_lock : require('subscription.amnezia_apply').with_lock;
    return with_lock(opts, function(lease) {
        let cursor = opts.cursor || require('uci').cursor();
        if (!cursor || cursor.load('network') == null) return { ok: false, error: 'Cannot inspect network configuration' };
        let choose = type(opts.choose) == 'function' ? opts.choose : require('subscription.amnezia_allocate').choose;
        let allocation;
        try { allocation = choose(cursor, opts); } catch (e) { return { ok: false, error: 'Cannot allocate AWG resources' }; }
        if (type(allocation) != 'object' || allocation.ok !== true)
            return { ok: false, error: 'Cannot allocate AWG resources' };
        let inner = {};
        for (let k in keys(opts)) inner[k] = opts[k];
        inner.apply_driver = lease.apply;
        inner.cleanup_driver = lease.cleanup;
        let before_revision = store.revision(dir, source, identity);
        let configs = store.load_configs(dir, source, identity);
        if (before_revision == null || type(configs) != 'array' || type(index) != 'int' || index < 0 || index >= length(configs))
            return { ok: false, error: 'Candidate unavailable' };
        let result = activate(dir, active_dir, source, identity, index, allocation, timeout_ms, inner);
        if (!result.ok || type(opts.publish) != 'function') return result;
        let published = false;
        try {
            if (store.revision(dir, source, identity) == before_revision)
                published = opts.publish(before_revision) === true;
        } catch (e) {}
        if (published) return result;
        let removed = false;
        try { removed = lease.cleanup(configs[index], allocation.name, allocation.table, allocation.priority).ok === true; } catch (e) {}
        if (removed && require('subscription.amnezia_active').peek(active_dir, source, identity) == before_revision)
            removed = fs.unlink(active_dir + '/' + source + '.json') === true;
        return { ok: false, error: 'Failed to publish source status', cleanup_required: !removed };
    });
}
return { apply_one, apply_one_and_record, activate, allocate_and_activate };
