// Persistent manual .conf source. This module does not install a guard, reload
// sing-box, or lock other writers. The caller must hold lifecycle/subscription
// locks and bind the source ID to the selected Forkop rule before publication.
let store = require('subscription.amnezia_store');
let active = require('subscription.amnezia_active');
let conf = require('subscription.amnezia_conf');
let fs = require('fs');
// ID is public metadata persisted in its owning Forkop UCI section. A new ID
// must be generated on creation; it must not be reused for a recreated rule.
function new_id() {
    let random = fs.open('/dev/urandom', 'r');
    if (!random) return null;
    let bytes = random.read(16); random.close();
    if (type(bytes) != 'string' || length(bytes) != 16) return null;
    let value = '';
    for (let i = 0; i < 16; i++) value += sprintf('%02x', ord(substr(bytes, i, 1)) & 255);
    return value;
}
function from_id(id) {
    if (type(id) != 'string' || !match(id, /^[0-9a-f]{32}$/)) return null;
    return { source: 'manual_' + id, identity: id + id };
}
function valid(source, identity) {
    return type(source) == 'string' && match(source, /^manual_[A-Za-z0-9_]{1,80}$/) != null &&
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
return { stage, publish, restore, new_id, from_id };
