// Apply one NEW AWG interface. This lock coordinates ArtakFork imports only;
// LuCI and other UCI writers do not use it. Network reload is global. Callers
// must also check kernel route/table collisions before invoking this module.
let fs = require('fs');
let uci = require('uci');
let importer = require('subscription.amnezia_import');
let routes = require('subscription.amnezia_routes');
let activation = require('subscription.amnezia_activate');
let runtime_check = require('subscription.amnezia_runtime_check');
let handshake = require('subscription.amnezia_handshake');
let conf = require('subscription.amnezia_conf');
let verifier = require('subscription.amnezia_verify');
let active_lease = null;
function valid_lease(lease) {
    if (lease == null || lease !== active_lease) return false;
    let current = fs.lstat(lease.lock_dir);
    return type(current) == 'object' && current.type == 'directory' &&
        current.uid == lease.uid && current.inode == lease.inode &&
        current.dev?.major == lease.major && current.dev?.minor == lease.minor && (current.mode & 63) == 0;
}

function normalized(section) {
    if (type(section) != 'object') return null;
    let out = {};
    for (let k in sort(keys(section)))
        if (substr(k, 0, 1) != '.' || k == '.type') out[k] = section[k];
    return sprintf('%J', out);
}
function apply_internal(text, name, table, priority, timeout_ms, opts, lease) {
    opts = opts || {};
    let config_dir = opts.config_dir || '/etc/config';
    let lock_dir = opts.lock_dir || '/tmp/artak-awg-apply.lock';
    let delta = lock_dir + '/delta';
    // Alternate directories exist only for isolated tests. A caller must never
    // pass paths derived from subscription content or unauthenticated input.
    let borrowed = lease != null;
    if (borrowed && (!valid_lease(lease) || lease.lock_dir != lock_dir)) return {ok:false,error:'Expired lock session'};
    if (!borrowed && !fs.mkdir(lock_dir)) return { ok: false, error: 'Another import is running or a stale lock exists' };
    let created_delta = false, cursor = null, names = [], snapshots = {}, committed = false;
    function process() {
    try {
        // Standard UCI saved deltas are shared with LuCI and may be applied by
        // network reload. Refuse if present; this does not eliminate races.
        if (config_dir == '/etc/config' && require('subscription.amnezia_pending').pending('/tmp/.uci/network'))
            return { ok: false, error: 'Pending network changes detected; apply or discard them first' };
        let available = runtime_check.check(table, priority, opts.runtime_runner);
        if (!available.ok) return available;
        let mark_audit = type(opts.mark_audit) == 'function' ? opts.mark_audit : require('subscription.amnezia_mark_audit').audit;
        let mark_result = mark_audit([0x18000000 | int(table)]);
        if (type(mark_result) != 'object' || mark_result.ok !== true) return {ok:false,error:'AWG mark audit failed'};
        if (borrowed && !valid_lease(lease)) return {ok:false,error:'AWG lock lost before staging'};
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
        let peer = cursor.get('network', name + '_peer', 'public_key');
        if (borrowed && !valid_lease(lease)) return {ok:false,error:'AWG lock lost before commit'};
        mark_result = mark_audit([0x18000000 | int(table)]);
        if (type(mark_result) != 'object' || mark_result.ok !== true) return {ok:false,error:'AWG mark audit failed before commit'};
        if (!importer.commit_staged(cursor).ok)
            return { ok: false, error: 'Commit uncertain; inspect network configuration' };
        committed = true;
        if (config_dir == '/etc/config' && require('subscription.amnezia_pending').pending('/tmp/.uci/network'))
            return { ok: false, error: 'Pending network changes appeared; inspect owned configuration' };
        available = runtime_check.check(table, priority, opts.runtime_runner);
        if (!available.ok) return { ok: false, error: 'Kernel routing changed; inspect owned configuration' };
        if (borrowed && !valid_lease(lease)) return {ok:false,error:'AWG lock lost after commit; inspect network'};
        let started = activation.start(name, addresses, timeout_ms, opts.runner, opts.pause, opts.now);
        if (started.ok) {
            let verified = handshake.verify(name, peer, timeout_ms, opts.handshake_runner || opts.runner,
                opts.pause, opts.now, opts.wall);
            if (verified.ok) return { ok: true, name, table, priority };
        }
        if (borrowed && !valid_lease(lease)) return {ok:false,error:'AWG lock lost; inspect network'};
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
        if (borrowed && !valid_lease(lease)) return {ok:false,error:'AWG lock lost before rollback; inspect network'};
        if (!check.commit('network'))
            return { ok: false, error: 'Activation failed; rollback commit uncertain' };
        if (borrowed && !valid_lease(lease)) return {ok:false,error:'AWG lock lost before reload; inspect network'};
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
    if (created_delta && (!borrowed || valid_lease(lease))) { fs.unlink(delta + '/network'); fs.rmdir(delta); }
    if (!borrowed) fs.rmdir(lock_dir);
    return result;
}
// For a just-created profile only. Exact UCI matching before and after stop
// avoids knowingly deleting modified sections. UCI offers no cross-process CAS:
// a noncooperating writer can still race between the final check and commit.
function cleanup_internal(text, name, table, priority, opts, lease) {
    opts = opts || {};
    let config_dir = opts.config_dir || '/etc/config';
    let lock_dir = opts.lock_dir || '/tmp/artak-awg-apply.lock', delta = lock_dir + '/delta';
    if (type(text) != 'string' || length(text) > 65536) return { ok:false, error:'Invalid cleanup request' };
    let parsed = conf.parse_conf(text);
    if (!parsed.ok || length(parsed.peers) != 1) return { ok:false, error:'Invalid cleanup configuration' };
    let ipv4 = false, ipv6 = false;
    for (let a in parsed.peers[0].allowed_ips) {
        if (a == '0.0.0.0/0') ipv4 = true;
        if (a == '::/0') ipv6 = true;
    }
    let plan = routes.prepare(name, table, priority, ipv4, ipv6);
    if (!plan.ok) return { ok:false, error:'Invalid cleanup allocation' };
    let borrowed = lease != null;
    if (borrowed && (!valid_lease(lease) || lease.lock_dir != lock_dir)) return {ok:false,error:'Expired lock session'};
    if (!borrowed && !fs.mkdir(lock_dir)) return { ok:false, error:'Another import is running or a stale lock exists' };
    let created_delta = false;
    function process() {
        try {
            if (config_dir == '/etc/config' && require('subscription.amnezia_pending').pending('/tmp/.uci/network'))
                return {ok:false,error:'Pending network changes detected'};
            if (!fs.chmod(lock_dir, 448) || !fs.mkdir(delta)) return {ok:false,error:'Could not create private UCI workspace'};
            created_delta = true;
            let c = uci.cursor(config_dir, delta, '');
            if (!c || c.load('network') == null || !verifier.verify_uci(c, parsed, name, table, priority, ipv4, ipv6).ok)
                return {ok:false,error:'Owned configuration differs; cleanup refused'};
            if (borrowed && !valid_lease(lease)) return {ok:false,error:'AWG lock lost before stop'};
            if (!activation.stop(name, opts.runner).ok)
                return {ok:false,error:'Could not stop interface; cleanup refused'};
            c = uci.cursor(config_dir, delta, '');
            if (!c || c.load('network') == null || !verifier.verify_uci(c, parsed, name, table, priority, ipv4, ipv6).ok)
                return {ok:false,error:'Owned configuration changed; cleanup refused'};
            let names = [name, name + '_peer'];
            for (let e in plan.entries) push(names, e.name);
            for (let n in names) if (c.delete('network', n) == null)
                return {ok:false,error:'Could not stage cleanup'};
            if (borrowed && !valid_lease(lease)) return {ok:false,error:'AWG lock lost before cleanup commit'};
            if (!c.commit('network')) return {ok:false,error:'Cleanup commit uncertain; inspect network'};
            if (config_dir == '/etc/config' && require('subscription.amnezia_pending').pending('/tmp/.uci/network'))
                return {ok:false,error:'Pending network changes appeared; reload refused'};
            if (borrowed && !valid_lease(lease)) return {ok:false,error:'AWG lock lost before reload; inspect network'};
            if (!activation.reload(opts.runner).ok) return {ok:false,error:'Cleanup committed but network reload failed'};
            return {ok:true};
        } catch (e) { return {ok:false,error:'Cleanup failed; inspect network'}; }
    }
    let result = process();
    if (created_delta && (!borrowed || valid_lease(lease))) { fs.unlink(delta + '/network'); fs.rmdir(delta); }
    if (!borrowed) fs.rmdir(lock_dir);
    return result;
}
function apply(text, name, table, priority, timeout_ms, opts) {
    return apply_internal(text, name, table, priority, timeout_ms, opts, null);
}
function cleanup(text, name, table, priority, opts) {
    return cleanup_internal(text, name, table, priority, opts, null);
}
// In-process session owns the same filesystem lock over allocation, all
// applies, manifest save, and cleanup. No token or bypass is exposed.
function with_lock(opts, callback) {
    opts = type(opts) == 'object' ? opts : {};
    if (type(callback) != 'function' || active_lease != null) return {ok:false,error:'Invalid or nested lock session'};
    let lock_dir = opts.lock_dir || '/tmp/artak-awg-apply.lock';
    if (!fs.mkdir(lock_dir)) return {ok:false,error:'Another import is running or a stale lock exists'};
    if (!fs.chmod(lock_dir, 448)) { fs.rmdir(lock_dir); return {ok:false,error:'Could not secure lock directory'}; }
    let st = fs.lstat(lock_dir);
    if (st == null || st.type != 'directory' || type(st.dev) != 'object' || (st.mode & 63) != 0) {
        fs.rmdir(lock_dir); return {ok:false,error:'Could not inspect lock directory'};
    }
    let lease = {lock_dir, uid:st.uid, inode:st.inode, major:st.dev.major, minor:st.dev.minor};
    active_lease = lease;
    let result;
    try {
        result = callback({
            valid: function() { return valid_lease(lease); },
            apply: function(text, name, table, priority, timeout_ms) { return apply_internal(text, name, table, priority, timeout_ms, opts, lease); },
            cleanup: function(text, name, table, priority) { return cleanup_internal(text, name, table, priority, opts, lease); }
        });
    } catch (e) { result = {ok:false,error:'Locked operation failed'}; }
    let owned = valid_lease(lease);
    active_lease = null;
    if (owned) fs.rmdir(lock_dir);
    else result = {ok:false,error:'AWG lock ownership changed; inspect runtime'};
    return result;
}
return { apply, cleanup, with_lock };
