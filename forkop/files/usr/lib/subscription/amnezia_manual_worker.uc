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
function run(text, section) {
    if (!require('subscription.amnezia_feature').enabled() || type(section) != 'string' ||
        !match(section, /^[A-Za-z0-9_]{1,80}$/)) return {ok:false};
    let stat = fs.readfile('/proc/self/stat');
    let pid = type(stat) == 'string' ? split(stat, ' ')[0] : '';
    if (!match(pid, /^[0-9]+$/) || !acquire(reload_lock, pid)) return {ok:false};
    let got_sub = false, delta = root + '/uci', created = false, result = {ok:false};
    try {
        got_sub = acquire(subscription_lock, pid);
        if (!got_sub || fs.stat('/tmp/.uci/forkop') != null || fs.stat('/tmp/.uci/network') != null)
            throw 'pending';
        if (!fs.mkdir(delta, 0700)) throw 'delta';
        created = true;
        let cursor = uci.cursor('/etc/config', delta, '');
        let bound = binding.bind(cursor, section, source.new_id);
        if (!bound.ok) throw 'bind';
        let dirs = {candidate:'/etc/forkop/awg-manual-candidates', last_good:'/etc/forkop/awg-last-good', active:'/etc/forkop/awg-active'};
        // Replacement needs a separate transactional swap. Never overwrite an
        // existing active mapping while its old interface is still in use.
        if (fs.stat(dirs.active + '/' + bound.source + '.json') != null) throw 'already-active';
        result = activation.activate(text, bound.source, bound.identity, dirs, {
            current: function() {
                if (fs.stat('/tmp/.uci/forkop') != null || fs.stat('/tmp/.uci/network') != null) return false;
                return binding.current(uci.cursor('/etc/config', delta, ''), section, bound);
            },
        });
    } catch (e) { result = {ok:false}; }
    if (created) { fs.unlink(delta + '/forkop'); fs.unlink(delta + '/network'); fs.rmdir(delta); }
    if (got_sub) release(subscription_lock);
    release(reload_lock);
    return result;
}
return { run };
