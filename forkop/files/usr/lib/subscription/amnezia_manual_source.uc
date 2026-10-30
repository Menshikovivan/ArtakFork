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
function publish(candidate_dir, last_good_dir, active_dir, source, identity, revision, entry, verify, generation_dir) {
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
    let generation = require('subscription.amnezia_generation');
    let record = { version:1, kind:'manual', source, identity, revision, url:'', user_agent:'', hwid:'', entries:[clean] };
    let old = generation.current_id(generation_dir, source);
    let staged = generation.stage(generation_dir, last_good_dir, record, verify);
    if (staged == null || !generation.switch_to(generation_dir, source, old, staged))
        return { ok: false, error: 'Manual verification or publication failed' };
    return { ok: true, source, identity, revision, generation:staged };
}
function restore(last_good_dir, generation_dir, source, identity, cursor, timeout_ms, opts) {
    if (!valid(source, identity)) return null;
    opts = type(opts) == 'object' ? opts : {};
    let settings = { matches_source: function(url, ua, hwid) { return url == '' && ua == '' && hwid == ''; },
        uci_check:opts.uci_check, live_check:opts.live_check };
    let result = require('subscription.amnezia_generation_restore').restore(generation_dir, last_good_dir, source, cursor, timeout_ms, settings);
    return type(result) == 'object' && result.identity == identity ? result.entries : null;
}
// Explicit legacy migration: never accept legacy if a current pointer already
// exists, and only publish after legacy restore/live checks and source guard.
function migrate(last_good_dir, active_dir, generation_dir, source, identity, cursor, timeout_ms, opts) {
    opts = type(opts) == 'object' ? opts : {};
    let generation = require('subscription.amnezia_generation');
    if (!valid(source, identity) || type(opts.current) != 'function' || opts.current() !== true ||
        fs.stat(generation_dir + '/' + source + '.current') != null) return false;
    let revision = active.peek(active_dir, source, identity);
    let entries = require('subscription.amnezia_restore').restore(last_good_dir, active_dir, source, identity, cursor, timeout_ms, opts);
    if (revision == null || type(entries) != 'array' || !length(entries) || opts.current() !== true ||
        active.peek(active_dir, source, identity) != revision) return false;
    let record = {version:1, kind:'manual', source, identity, revision, url:'', user_agent:'', hwid:'', entries};
    let id = generation.stage(generation_dir, last_good_dir, record, function() { return opts.current() === true; });
    return id != null && opts.current() === true && generation.switch_to(generation_dir, source, null, id);
}
return { stage, publish, restore, migrate, new_id, from_id };
