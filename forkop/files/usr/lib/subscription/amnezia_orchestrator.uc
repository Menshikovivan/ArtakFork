// Single-owner transition orchestration. This internal module does not accept
// CLI parameters or perform a transition without trusted in-process hooks.
// Lock order is reload -> subscription -> AWG; operations must use the AWG
// lease passed to the hook factory and must not recursively invoke reload.
let fs = require('fs');
let swap = require('subscription.amnezia_swap');
let apply = require('subscription.amnezia_apply');
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
    function command(args) {
        let parts = ['ucode', '-L', lib, state];
        for (let a in args) push(parts, a);
        return system(join(' ', map(parts, x => quote(x))) + ' >/dev/null 2>&1') == 0;
    }
    function acquire(path) { return owner != null && command(['acquire-runtime-dir-lock-wait', path, owner, '2']); }
    function release(path) {
        let current = fs.readfile(path + '/pid');
        if (type(current) != 'string' || trim(current) != owner) return false;
        return command(['release-runtime-dir-lock', path]) && fs.stat(path) == null;
    }
    return { acquire_reload:function() { return acquire(reload); }, acquire_subscription:function() { return acquire(subscription); },
        release_subscription:function() { return release(subscription); }, release_reload:function() { return release(reload); }, with_awg:apply.with_lock };
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
            let ops = factory(lease);
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
return { execute, recover };
