// Migrate a verified legacy AWG-only status + manifest into one immutable
// generation. Caller holds subscription/network/lifecycle locks.
let fs = require('fs');
let status = require('subscription.amnezia_status');
let active = require('subscription.amnezia_active');
let legacy = require('subscription.amnezia_restore');
let generation = require('subscription.amnezia_generation');
function migrate(status_dir, active_dir, good_dir, generation_dir, source, cursor, timeout_ms, opts) {
    opts = type(opts) == 'object' ? opts : {};
    if (type(opts.current) != 'function' || opts.current() !== true ||
        fs.stat(generation_dir + '/' + source + '.current') != null) return false;
    let s = status.read(status_dir, source);
    if (s == null || active.peek(active_dir, source, s.identity) != s.revision) return false;
    let entries = legacy.restore(good_dir, active_dir, source, s.identity, cursor, timeout_ms, opts);
    if (type(entries) != 'array' || !length(entries) || opts.current() !== true ||
        active.peek(active_dir, source, s.identity) != s.revision) return false;
    let record = { version:1, kind:'subscription', source, identity:s.identity, revision:s.revision,
        url:s.url, user_agent:s.user_agent, hwid:s.hwid, entries };
    let id = generation.stage(generation_dir, good_dir, record, function() { return opts.current() === true; });
    return id != null && opts.current() === true && generation.switch_to(generation_dir, source, null, id);
}
return { migrate };
