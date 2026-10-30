// Caller must hold Forkop's subscription/lifecycle locks throughout. This
// orchestrator acquires the AWG network lock using the backend session.
// Publication is not equivalent to a usable node: snapshot and firewall guard
// must be rebuilt and verified before sing-box may reference this interface.
let manual = require('subscription.amnezia_manual_source');
let allocate = require('subscription.amnezia_allocate');
let conf = require('subscription.amnezia_conf');
let backend = require('subscription.amnezia_apply');
let verifier = require('subscription.amnezia_verify');

function activate(text, source, identity, dirs, opts) {
    opts = type(opts) == 'object' ? opts : {};
    if (type(dirs) != 'object' || type(dirs.candidate) != 'string' ||
        type(dirs.last_good) != 'string' || type(dirs.active) != 'string' || type(dirs.generation) != 'string' ||
        type(opts.current) != 'function') return { ok: false, error: 'Invalid manual activation context' };
    let parsed = conf.parse_conf(text);
    if (!parsed.ok || length(parsed.peers) != 1) return { ok: false, error: 'Invalid manual configuration' };
    let lease = type(opts.with_lock) == 'function' ? opts.with_lock : backend.with_lock;
    return lease(opts, function(session) {
        if (opts.current() !== true) return { ok: false, error: 'Manual source changed' };
        let candidate = manual.stage(dirs.candidate, source, identity, text);
        if (!candidate.ok) return candidate;
        let cursor = type(opts.cursor) == 'object' || type(opts.cursor) == 'resource' ? opts.cursor : require('uci').cursor();
        let chooser = type(opts.choose) == 'function' ? opts.choose : allocate.choose;
        let chosen = chooser(cursor, opts);
        if (type(chosen) != 'object' || chosen.ok !== true) return { ok: false, error: 'Cannot allocate interface' };
        if (opts.current() !== true) return { ok: false, error: 'Manual source changed' };
        let applied = session.apply(text, chosen.name, chosen.table, chosen.priority, 5000);
        if (type(applied) != 'object' || applied.ok !== true) return { ok: false, error: 'Interface activation failed', diagnostic: applied?.diagnostic || 'activation_failed', cleanup_required: type(applied) != 'object' || applied.cleanup_required === true };
        let cleanup = function() {
            try { let result = session.cleanup(text, chosen.name, chosen.table, chosen.priority); return result && result.ok === true; }
            catch (e) { return false; }
        };
        let ipv4 = false, ipv6 = false;
        for (let ip in parsed.peers[0].allowed_ips) {
            if (ip == '0.0.0.0/0') ipv4 = true;
            if (ip == '::/0') ipv6 = true;
        }
        let verify = function(entry) {
            if (opts.current() !== true) return false;
            let c = type(opts.verify_cursor) == 'function' ? opts.verify_cursor() : require('uci').cursor();
            if (!c || c.load('network') == null) return false;
            let uci_check = type(opts.uci_check) == 'function' ? opts.uci_check : verifier.verify_uci;
            let live_check = type(opts.live_check) == 'function' ? opts.live_check : verifier.verify;
            let u = uci_check(c, parsed, entry.name, entry.table, entry.priority, ipv4, ipv6);
            let live = live_check(entry.name, entry.table, entry.priority, parsed.interface.addresses,
                parsed.peers[0].public_key, ipv4, ipv6, 5000);
            return type(u) == 'object' && u.ok === true && type(live) == 'object' && live.ok === true && opts.current() === true;
        };
        let result = null;
        try { result = manual.publish(dirs.candidate, dirs.last_good, dirs.active, source, identity, candidate.revision, chosen, verify, dirs.generation); }
        catch (e) {}
        if (type(result) != 'object' || !result.ok) return { ok: false, error: 'Manual publication failed', diagnostic: 'publication_failed', cleanup_required: !cleanup() };
        return { ok: true, source, identity, revision: candidate.revision, name: chosen.name };
    });
}
return { activate };
