// Manual import under lifecycle locks. No config or key material enters argv.
let fs = require('fs');
let uci = require('uci');
let binding = require('subscription.amnezia_manual_binding');
let source = require('subscription.amnezia_manual_source');
let activation = require('subscription.amnezia_manual_activate');
let root = '/tmp/artak-awg-job';
let reload_lock = '/var/run/forkop.reload.lock';
let subscription_lock = '/var/run/forkop/subscription-update.lock';
function acquire(path, pid) {
    if (!fs.mkdir(path, 0700)) return false;
    if (fs.writefile(path + '/pid', pid + '\n') == null) { fs.rmdir(path); return false; }
    return true;
}
function release(path) { fs.unlink(path + '/pid'); fs.rmdir(path); }
function run(text, section, opts) {
    opts = type(opts) == 'object' ? opts : {};
    let feature = type(opts.feature) == 'function' ? opts.feature : require('subscription.amnezia_feature').enabled;
    let config_dir = opts.config_dir || '/etc/config';
    let job_root = opts.job_root || root;
    let rlock = opts.reload_lock || reload_lock, slock = opts.subscription_lock || subscription_lock;
    let pending = type(opts.pending) == 'function' ? opts.pending : function() {
        return fs.stat('/tmp/.uci/forkop') != null || fs.stat('/tmp/.uci/network') != null;
    };
    if (!feature() || type(section) != 'string' ||
        !match(section, /^[A-Za-z0-9_]{1,80}$/)) return {ok:false};
    let stat = fs.readfile('/proc/self/stat');
    let pid = type(stat) == 'string' ? split(stat, ' ')[0] : '';
    if (!match(pid, /^[0-9]+$/) || !acquire(rlock, pid)) return {ok:false};
    let got_sub = false, delta = job_root + '/uci', created = false, result = {ok:false};
    try {
        got_sub = acquire(slock, pid);
        if (!got_sub || pending())
            throw 'pending';
        if (!fs.mkdir(delta, 0700)) throw 'delta';
        created = true;
        let cursor = uci.cursor(config_dir, delta, '');
        let bound = binding.bind(cursor, section, source.new_id);
        if (!bound.ok) throw 'bind';
        let dirs = opts.dirs || {candidate:'/etc/forkop/awg-manual-candidates', last_good:'/etc/forkop/awg-last-good', active:'/etc/forkop/awg-active'};
        // Replacement needs a separate transactional swap. Never overwrite an
        // existing active mapping while its old interface is still in use.
        if (fs.stat(dirs.active + '/' + bound.source + '.json') != null) throw 'already-active';
        let apply = type(opts.activate) == 'function' ? opts.activate : activation.activate;
        result = apply(text, bound.source, bound.identity, dirs, {
            current: function() {
                if (!feature() || pending()) return false;
                return binding.current(uci.cursor(config_dir, delta, ''), section, bound);
            },
        });
    } catch (e) { result = {ok:false}; }
    if (created) { fs.unlink(delta + '/forkop'); fs.unlink(delta + '/network'); fs.rmdir(delta); }
    if (got_sub) release(slock);
    release(rlock);
    return result;
}
return { run };
