// Read a single published generation and verify its corresponding live AWG
// state. The source-profile callback sees private URL metadata in memory only;
// returned entries contain no credentials or source metadata.
let generation = require('subscription.amnezia_generation');
let store = require('subscription.amnezia_store');
let verifier = require('subscription.amnezia_verify');
function inspect(dir, good_dir, source, current, cursor, timeout_ms, opts) {
    opts = type(opts) == 'object' ? opts : {};
    if (type(opts.matches_source) != 'function') return null;
    if (current == null) return null;
    let record = generation.read_generation(dir, source, current);
    if (record == null) return null;
    try { if (opts.matches_source(record.url, record.user_agent, record.hwid) !== true) return null; }
    catch (e) { return null; }
    let path = good_dir + '/' + record.revision;
    if (store.revision(path, source, record.identity) != record.revision) return null;
    let profiles = store.load(path, source, record.identity);
    if (type(profiles) != 'array') return null;
    let uci_check = type(opts.uci_check) == 'function' ? opts.uci_check : verifier.verify_uci;
    let live_check = type(opts.live_check) == 'function' ? opts.live_check : verifier.verify;
    for (let entry in record.entries) {
        let profile = profiles[entry.index];
        if (type(profile) != 'object' || !profile.ok || length(profile.peers) != 1) return null;
        let ipv4 = false, ipv6 = false;
        for (let ip in profile.peers[0].allowed_ips) {
            if (ip == '0.0.0.0/0') ipv4 = true;
            if (ip == '::/0') ipv6 = true;
        }
        try {
            let a = uci_check(cursor, profile, entry.name, entry.table, entry.priority, ipv4, ipv6);
            if (type(a) != 'object' || a.ok !== true) return null;
            let b = live_check(entry.name, entry.table, entry.priority, profile.interface.addresses,
                profile.peers[0].public_key, ipv4, ipv6, timeout_ms);
            if (type(b) != 'object' || b.ok !== true) return null;
        } catch (e) { return null; }
    }
    if (generation.read_generation(dir, source, current) == null || store.revision(path, source, record.identity) != record.revision) return null;
    return { generation:current, revision:record.revision, identity:record.identity, entries:record.entries };
}
function restore(dir, good_dir, source, cursor, timeout_ms, opts) {
    let current = generation.current_id(dir, source);
    let result = inspect(dir, good_dir, source, current, cursor, timeout_ms, opts);
    return result != null && generation.current_id(dir, source) == current ? result : null;
}
return { restore, inspect };
