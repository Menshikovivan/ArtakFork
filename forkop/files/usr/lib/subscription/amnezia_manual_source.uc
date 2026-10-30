// Persistent manual .conf source. This module does not install a guard, reload
// sing-box, or lock other writers. The caller must hold lifecycle/subscription
// locks and bind the source ID to the selected Forkop rule before publication.
let store = require('subscription.amnezia_store');
let active = require('subscription.amnezia_active');
let conf = require('subscription.amnezia_conf');
function valid(source, identity) {
    return type(source) == 'string' && match(source, /^manual_[a-z0-9_]{1,80}$/) != null &&
        type(identity) == 'string' && match(identity, /^[0-9a-f]{64}$/) != null;
}
// No secrets in result. A new candidate does not alter the active manifest.
function stage(candidate_dir, source, identity, text) {
    if (!valid(source, identity) || type(text) != 'string' || length(text) > 65536)
        return { ok: false, error: 'Invalid manual source' };
    let parsed = conf.parse_conf(text);
    if (!parsed.ok || length(parsed.peers) != 1) return { ok: false, error: 'Invalid manual configuration' };
    if (!store.save(candidate_dir, source, identity, 'vpn://' + b64enc(text)))
        return { ok: false, error: 'Cannot stage manual configuration' };
    let revision = store.revision(candidate_dir, source, identity);
    return revision == null ? { ok: false, error: 'Cannot inspect staged configuration' } : { ok: true, revision };
}
// verify must check real UCI configuration, route state and handshake. The
// immutable promotion happens before manifest update; failures retain the
// previously published manifest. Recheck source/rule guard immediately before
// calling this function, under the same lifecycle locks.
function publish(candidate_dir, last_good_dir, active_dir, source, identity, revision, entry, verify) {
    if (!valid(source, identity) || type(verify) != 'function' || type(entry) != 'object' ||
        type(revision) != 'string' || !match(revision, /^[0-9a-f]{64}$/))
        return { ok: false, error: 'Invalid manual publication' };
    if (store.revision(candidate_dir, source, identity) != revision)
        return { ok: false, error: 'Manual candidate changed' };
    if (!store.promote(candidate_dir, last_good_dir, source, identity, revision))
        return { ok: false, error: 'Cannot preserve manual revision' };
    if (store.revision(candidate_dir, source, identity) != revision)
        return { ok: false, error: 'Manual candidate changed' };
    let clean = { index: 0, name: entry.name, table: entry.table, priority: entry.priority };
    if (!active.save(active_dir, source, identity, revision, [clean], verify))
        return { ok: false, error: 'Manual verification or publication failed' };
    return { ok: true, source, identity, revision };
}
function restore(last_good_dir, active_dir, source, identity, cursor, timeout_ms, opts) {
    if (!valid(source, identity)) return null;
    return require('subscription.amnezia_restore').restore(last_good_dir, active_dir, source, identity, cursor, timeout_ms, opts);
}
return { stage, publish, restore };
