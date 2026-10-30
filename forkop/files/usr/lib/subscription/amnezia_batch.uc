// First activation of a complete AWG subscription under one in-process lock.
// Existing active sources are rejected until their swap and guard lifecycle
// have a transactional implementation. Credentials remain in memory only.
let fs = require('fs');
let store = require('subscription.amnezia_store');
let active = require('subscription.amnezia_active');
let conf = require('subscription.amnezia_conf');
let verifier = require('subscription.amnezia_verify');
let apply = require('subscription.amnezia_apply');
let allocator = require('subscription.amnezia_allocate');

function activate(dir, active_dir, good_dir, source, identity, timeout_ms, opts) {
    opts = type(opts) == 'object' ? opts : {};
    let with_lock = type(opts.with_lock) == 'function' ? opts.with_lock : apply.with_lock;
    return with_lock(opts, function(lease) {
        let revision = store.revision(dir, source, identity), configs = store.load_configs(dir, source, identity);
        if (revision == null || type(configs) != 'array' || !length(configs) || length(configs) > 32 ||
            type(active_dir) != 'string' || active_dir == '' || active_dir == '/' ||
            fs.stat(active_dir + '/' + source + '.json') != null)
            return { ok: false, error: 'Candidate unavailable or source already active' };
        function network_cursor() {
            let c = opts.cursor || require('uci').cursor();
            return c && c.load('network') != null ? c : null;
        }
        if (!network_cursor()) return { ok: false, error: 'Cannot inspect network' };
        let choose = type(opts.choose) == 'function' ? opts.choose : allocator.choose;
        let uci_check = type(opts.uci_check) == 'function' ? opts.uci_check : verifier.verify_uci;
        let live_check = type(opts.live_check) == 'function' ? opts.live_check : verifier.verify;
        let entries = [], parsed = [];
        function verify_entry(entry) {
            let p = parsed[entry.index];
            let cursor = network_cursor();
            if (p == null || cursor == null) return false;
            let ipv4 = false, ipv6 = false;
            for (let ip in p.peers[0].allowed_ips) {
                if (ip == '0.0.0.0/0') ipv4 = true;
                if (ip == '::/0') ipv6 = true;
            }
            let u = uci_check(cursor, p, entry.name, entry.table, entry.priority, ipv4, ipv6);
            if (type(u) != 'object' || u.ok !== true) return false;
            let l = live_check(entry.name, entry.table, entry.priority, p.interface.addresses, p.peers[0].public_key, ipv4, ipv6, timeout_ms);
            return type(l) == 'object' && l.ok === true;
        }
        function rollback() {
            let ok = true;
            for (let i = length(entries) - 1; i >= 0; i--) {
                let e = entries[i], r;
                try { r = lease.cleanup(configs[e.index], e.name, e.table, e.priority); } catch (ignored) { r = null; }
                if (type(r) != 'object' || r.ok !== true) ok = false;
            }
            if (ok && active.peek(active_dir, source, identity) == revision)
                ok = fs.unlink(active_dir + '/' + source + '.json') === true;
            return ok;
        }
        function process() {
        for (let i = 0; i < length(configs); i++) {
            let p = conf.parse_conf(configs[i]);
            if (!p.ok || length(p.peers) != 1) return { ok: false, error: 'Invalid candidate', cleanup_required: !rollback() };
            push(parsed, p);
            let a; try { a = choose(network_cursor(), opts); } catch (ignored) { a = null; }
            if (type(a) != 'object' || a.ok !== true) return { ok: false, error: 'No AWG allocation', cleanup_required: !rollback() };
            let result; try { result = lease.apply(configs[i], a.name, a.table, a.priority, timeout_ms); } catch (ignored) { result = null; }
            if (type(result) != 'object' || result.ok !== true) {
                rollback();
                // apply may have failed after a commit with uncertain state.
                return { ok: false, error: 'AWG activation failed; inspect owned interface', cleanup_required: true };
            }
            let entry = { index: i, name: a.name, table: a.table, priority: a.priority };
            push(entries, entry);
            if (!verify_entry(entry)) return { ok: false, error: 'AWG verification failed', cleanup_required: !rollback() };
        }
        if (store.revision(dir, source, identity) != revision || !store.promote(dir, good_dir, source, identity, revision) ||
            !active.save(active_dir, source, identity, revision, entries, verify_entry))
            return { ok: false, error: 'AWG manifest publication failed', cleanup_required: !rollback() };
        let published = type(opts.publish) != 'function';
        try { if (!published) published = store.revision(dir, source, identity) == revision && opts.publish(revision) === true; } catch (ignored) {}
        if (!published) return { ok: false, error: 'Source status publication failed', cleanup_required: !rollback() };
        return { ok: true, count: length(entries) };
        }
        try { return process(); }
        catch (e) { return { ok: false, error: 'Batch failed; inspect owned interfaces', cleanup_required: !rollback() }; }
    });
}
return { activate };
