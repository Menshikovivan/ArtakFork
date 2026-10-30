// Single-owner transition orchestration. This internal module does not accept
// CLI parameters or perform a transition without trusted in-process hooks.
// Lock order is reload -> subscription -> AWG; operations must use the AWG
// lease passed to the hook factory and must not recursively invoke reload.
let fs = require('fs');
let swap = require('subscription.amnezia_swap');
function quote(s) { return "'" + replace(s, /'/g, "'\\''") + "'"; }
function pid() {
    let stat = fs.readfile('/proc/self/stat');
    if (type(stat) != 'string') return null;
    let n = split(stat, ' ')[0];
    return match(n, /^[0-9]+$/) ? n : null;
}
function real_locks(opts) {
    let lib = opts.lib || '/usr/lib', state = lib + '/service/state.uc';
    let owner = pid(), reload = opts.reload_lock || '/var/run/forkop.reload.lock';
    let subscription = opts.subscription_lock || '/var/run/forkop/subscription-update.lock';
    let identities = {};
    function command(args) {
        let parts = ['ucode', '-L', lib, state];
        for (let a in args) push(parts, a);
        return system(join(' ', map(parts, x => quote(x))) + ' >/dev/null 2>&1') == 0;
    }
    function acquire(path) {
        if (owner == null || !command(['acquire-runtime-dir-lock-wait', path, owner, '2'])) return false;
        let s = fs.lstat(path);
        if (s == null || s.type != 'directory' || type(s.dev) != 'object' || s.inode == null || s.uid == null) return false;
        identities[path] = { uid:s.uid, inode:s.inode, major:s.dev.major, minor:s.dev.minor };
        return owned(path);
    }
    function release(path) {
        if (!owned(path)) return false;
        return command(['release-runtime-dir-lock', path]) && fs.stat(path) == null;
    }
    function owned(path) {
        let value = fs.readfile(path + '/pid'), s = fs.lstat(path), expected = identities[path];
        return owner != null && expected != null && type(value) == 'string' && trim(value) == owner &&
            s != null && s.type == 'directory' && type(s.dev) == 'object' && s.uid == expected.uid &&
            s.inode == expected.inode && s.dev.major == expected.major && s.dev.minor == expected.minor;
    }
    return { acquire_reload:function() { return acquire(reload); }, acquire_subscription:function() { return acquire(subscription); },
        release_subscription:function() { return release(subscription); }, release_reload:function() { return release(reload); },
        owned:function() { return owned(reload) && owned(subscription); },
        with_awg:function(options, callback) { return require('subscription.amnezia_apply').with_lock(options, callback); } };
}
function guarded(factory, opts, run) {
    if (type(factory) != 'function' || type(run) != 'function') return {ok:false,error:'Invalid transition request'};
    opts = type(opts) == 'object' ? opts : {};
    // Injection is for isolated in-process tests, never supplied by RPC or CLI.
    let locks = type(opts.locks) == 'object' ? opts.locks : real_locks(opts);
    let reload_held = false, subscription_held = false, result = {ok:false,error:'Transition lock failed'};
    function process() {
        if (!locks.acquire_reload()) return result;
        reload_held = true;
        if (!locks.acquire_subscription()) return result;
        subscription_held = true;
        return locks.with_awg(opts, function(lease) {
            let holds = function() {
                return reload_held && subscription_held && type(locks.owned) == 'function' && locks.owned() === true &&
                    type(lease.valid) == 'function' && lease.valid() === true;
            };
            if (!holds()) return {ok:false,error:'Transition ownership unavailable'};
            let ops = factory(lease, holds);
            if (type(ops) != 'object') return {ok:false,error:'Transition operations unavailable'};
            return run(ops);
        });
    }
    try {
        result = process();
    } catch (e) { result = {ok:false,error:'Transition failed'}; }
    try { if (subscription_held && !locks.release_subscription()) result = {ok:false,error:'Subscription lock release failed'}; }
    catch (e) { result = {ok:false,error:'Subscription lock release failed'}; }
    try { if (reload_held && !locks.release_reload()) result = {ok:false,error:'Reload lock release failed'}; }
    catch (e) { result = {ok:false,error:'Reload lock release failed'}; }
    return result;
}
function execute(factory, journal_dir, generation_dir, source, old_id, new_id, opts) {
    return guarded(factory, opts, function(ops) { return swap.execute_journaled(ops, journal_dir, generation_dir, source, old_id, new_id); });
}
function recover(factory, journal_dir, generation_dir, source, opts) {
    return guarded(factory, opts, function(ops) { return swap.recover(ops, journal_dir, generation_dir, source); });
}

// Start an update from a candidate while preserving the old current pointer.
// The prepare and swap journals share journal_dir so startup recovery sees
// either checkpoint. Trusted runtime hooks must install/verify union guard and
// reload the managed sing-box in-process without reacquiring lifecycle locks.
function prepare_and_execute(factory, dirs, source, old_id, identity, metadata, timeout_ms, opts) {
    opts = type(opts) == 'object' ? opts : {};
    if (type(factory) != 'function' || type(dirs) != 'object' || type(opts.current) != 'function')
        return {ok:false,error:'Invalid transition request'};
    return guarded(function(lease, holds) { return {lease, holds}; }, opts, function(ctx) {
        let prepare = require('subscription.amnezia_prepare_journal');
        let apply_plan = require('subscription.amnezia_prepare_apply');
        let cursor = opts.cursor || require('uci').cursor();
        let inner = {};
        for (let k in keys(opts)) inner[k] = opts[k];
        inner.current = function() { return ctx.holds() && opts.current() === true; };
        if (!inner.current()) return {ok:false,error:'Source or lock changed'};
        let plan = prepare.reserve(dirs.journal, dirs.generation, dirs.candidate, dirs.good, source, old_id, identity, cursor, inner);
        if (plan == null) return {ok:false,error:'Cannot reserve new interfaces',recovery_required:true};
        let staged = apply_plan.run(ctx.lease, dirs.journal, dirs.generation, dirs.good, source, metadata, timeout_ms, inner);
        if (type(staged) != 'object' || staged.ok !== true) return staged;
        if (!inner.current() || !prepare.handoff(dirs.journal, dirs.journal, dirs.generation, source, staged.generation))
            return {ok:false,error:'Cannot hand off preparation journal',recovery_required:true};
        let ops;
        try { ops = factory(ctx.lease, ctx.holds, staged.generation); } catch (e) { ops = null; }
        if (type(ops) != 'object' || !inner.current()) return {ok:false,error:'Transition operations unavailable',recovery_required:true};
        let checked = {};
        for (let name in ['prepare','snapshot_revisions','install_union','verify_union','reload','verify_new',
                          'restore_old','verify_old','discard_new','retire_old']) {
            let n = name, operation = ops[n];
            if (type(operation) != 'function') return {ok:false,error:'Transition operations unavailable',recovery_required:true};
            checked[n] = function() {
                if (!ctx.holds()) return false;
                if (n != 'restore_old' && n != 'verify_old' && n != 'discard_new' && !inner.current()) return false;
                return operation();
            };
        }
        if (type(ops.finalize_new) != 'function') return {ok:false,error:'Transition finalizer unavailable',recovery_required:true};
        checked.finalize_new = function() { return inner.current() && ctx.holds() && ops.finalize_new() === true; };
        return swap.execute_journaled(checked, dirs.journal, dirs.generation, source, old_id, staged.generation);
    });
}
return { execute, recover, prepare_and_execute };
