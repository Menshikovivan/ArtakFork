// Internal restoration adapter. The caller must hold subscription and network
// lifecycle locks; readiness is a snapshot and is not a lifetime guarantee.
let store = require('subscription.amnezia_store');
let active = require('subscription.amnezia_active');
let verifier = require('subscription.amnezia_verify');

function restore(dir, manifest_dir, source, identity, cursor, timeout_ms, opts) {
    let revision = active.peek(manifest_dir, source, identity);
    if (revision == null) return null;
    let immutable_dir = dir + '/' + revision;
    if (store.revision(immutable_dir, source, identity) != revision) return null;
    let profiles = store.load(immutable_dir, source, identity);
    if (revision == null || type(profiles) != 'array') return null;
    opts = type(opts) == 'object' ? opts : {};
    let uci_check = type(opts.uci_check) == 'function' ? opts.uci_check : verifier.verify_uci;
    let live_check = type(opts.live_check) == 'function' ? opts.live_check : verifier.verify;
    let verify = function(entry) {
        let parsed = profiles[entry.index];
        if (type(parsed) != 'object' || !parsed.ok || length(parsed.peers) != 1) return false;
        let ipv4 = false, ipv6 = false;
        for (let ip in parsed.peers[0].allowed_ips) {
            if (ip == '0.0.0.0/0') ipv4 = true;
            if (ip == '::/0') ipv6 = true;
        }
        let a = uci_check(cursor, parsed, entry.name, entry.table, entry.priority, ipv4, ipv6);
        if (type(a) != 'object' || a.ok !== true) return false;
        let b = live_check(entry.name, entry.table, entry.priority, parsed.interface.addresses,
            parsed.peers[0].public_key, ipv4, ipv6, timeout_ms);
        return type(b) == 'object' && b.ok === true;
    };
    let entries = active.restore(manifest_dir, source, identity, revision, verify);
    if (entries == null || store.revision(immutable_dir, source, identity) != revision ||
        active.peek(manifest_dir, source, identity) != revision) return null;
    return entries;
}
return { restore };
