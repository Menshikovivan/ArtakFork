// Durable backup of section metadata for AWG sing-box rollback. All paths are
// trusted internal paths under private swap state; caller holds lifecycle locks.
let fs = require('fs');
let common = require('core.common');
function entries(dir, missing_ok) {
    let st = fs.lstat(dir);
    if (st == null) return missing_ok ? [] : null;
    if (st.type != 'directory') return null;
    let names = fs.lsdir(dir);
    if (type(names) != 'array' || length(names) > 1024) return null;
    let result = [], total = 0;
    for (let name in sort(names)) {
        if (!match(name, /^[A-Za-z0-9_-]+\.json$/)) return null;
        let path = dir + '/' + name, file = fs.lstat(path);
        if (file == null || file.type != 'file' || file.size > 4194304) return null;
        total += file.size;
        if (total > 33554432) return null;
        let data = fs.readfile(path);
        if (type(data) != 'string' || length(data) != file.size) return null;
        push(result, {name, data});
    }
    return result;
}
function same(a, b) {
    if (type(a) != 'array' || type(b) != 'array' || length(a) != length(b)) return false;
    for (let i = 0; i < length(a); i++) if (a[i].name != b[i].name || a[i].data != b[i].data) return false;
    return true;
}
function write_copy(dir, data) {
    if (!fs.mkdir(dir, 0700)) return false;
    for (let entry in data)
        if (common.write_private_file(dir + '/' + entry.name, entry.data) == null) return false;
    return true;
}
function capture(dir, live, staged) {
    let old = entries(live, true), next = entries(staged, true);
    if (old == null || next == null) return false;
    // No generated section cache means commit leaves the existing cache alone.
    if (fs.lstat(staged) == null) next = old;
    if (!write_copy(dir + '/cache-old', old) || !write_copy(dir + '/cache-new', next)) return false;
    // Reject changes during copy, before the config or cache can be committed.
    return same(old, entries(live, true)) &&
        (fs.lstat(staged) == null ? same(next, old) : same(next, entries(staged, false))) &&
        common.write_private_file(dir + '/cache-ready', '1\n') != null;
}
function restore(dir, live, publish) {
    if (type(publish) != 'function' || fs.readfile(dir + '/cache-ready') != '1\n') return false;
    let old = entries(dir + '/cache-old', false), next = entries(dir + '/cache-new', false), current = entries(live, true);
    if (old == null || next == null || current == null) return false;
    if (same(current, old)) return true;
    // A missing live directory is safe to reconstruct after interrupted
    // publication; any other unexpected change is preserved for inspection.
    if (fs.lstat(live) != null && !same(current, next)) return false;
    let replay = dir + '/cache-replay.section-cache';
    if (fs.lstat(replay) != null) {
        if (!same(entries(replay, false), old)) return false;
    } else if (!write_copy(replay, old)) return false;
    if (publish(dir + '/cache-replay') !== true) return false;
    return same(old, entries(live, true));
}
// A reboot removes the runtime cache. Recreate only a missing directory from
// the captured new generation; never overwrite a present, unexpected cache.
function recover_new(dir, live, publish) {
    if (type(publish) != 'function' || fs.readfile(dir + '/cache-ready') != '1\n') return false;
    let next = entries(dir + '/cache-new', false);
    if (next == null) return false;
    if (fs.lstat(live) != null) return same(entries(live, false), next);
    let replay = dir + '/cache-new-replay.section-cache';
    if (fs.lstat(replay) != null) {
        if (!same(entries(replay, false), next)) return false;
    } else if (!write_copy(replay, next)) return false;
    return publish(dir + '/cache-new-replay') === true && same(next, entries(live, false));
}
function verify(dir, live, which) {
    if ((which != 'old' && which != 'new') || fs.readfile(dir + '/cache-ready') != '1\n') return false;
    return same(entries(dir + '/cache-' + which, false), entries(live, true));
}
return { capture, restore, verify, recover_new };
