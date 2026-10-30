// Private immutable generation plus a single atomic pointer. Each generation
// contains source metadata (including the subscription URL) and no VPN keys.
// Callers hold lifecycle/subscription/network locks across stage and switch.
let fs = require('fs');
let common = require('core.common');
let routes = require('subscription.amnezia_routes');
let identity = require('subscription.amnezia_identity');
let store = require('subscription.amnezia_store');
function hash_ok(s) { return type(s) == 'string' && match(s, /^[0-9a-f]{64}$/) != null; }
function source_ok(s) { return type(s) == 'string' && match(s, /^[A-Za-z0-9_-]{1,100}$/) != null; }
function digest(path) {
    let q = "'" + replace(path, /'/g, "'\\''") + "'", p = fs.popen('sha256sum ' + q + ' 2>/dev/null', 'r');
    if (!p) return null;
    let out = p.read('all'), status = p.close();
    if (status != 0 || type(out) != 'string') return null;
    let hash = split(trim(out), /[ \t\r\n]+/)[0];
    return hash_ok(hash) ? hash : null;
}
function checked(record) {
    let kind = record?.kind || 'subscription';
    if (type(record) != 'object' || record.version != 1 || !source_ok(record.source) ||
        !hash_ok(record.identity) || !hash_ok(record.revision) ||
        (kind != 'subscription' && kind != 'manual') || type(record.url) != 'string' ||
        (kind == 'subscription' && record.url == '') || type(record.user_agent) != 'string' || type(record.hwid) != 'string' ||
        type(record.entries) != 'array' || !length(record.entries) || length(record.entries) > 32) return null;
    if (kind == 'manual') {
        let matched = match(record.source, /^manual_([0-9a-f]{32})$/);
        if (matched == null || record.identity != matched[1] + matched[1] || record.url != '' ||
            record.user_agent != '' || record.hwid != '') return null;
    }
    let entries = [], names = {}, tables = {}, indices = {}, priorities = {};
    for (let e in record.entries) {
        if (type(e) != 'object' || type(e.index) != 'int' || e.index < 0 || e.index >= 32 ||
            !routes.prepare(e.name, e.table, e.priority, true, false).ok) return null;
        let priority = +e.priority;
        if (names[e.name] || tables[e.table] || indices['' + e.index] || priorities['' + priority] || priorities['' + (priority + 1)]) return null;
        names[e.name] = true; tables[e.table] = true; indices['' + e.index] = true;
        priorities['' + priority] = true; priorities['' + (priority + 1)] = true;
        push(entries, { index:e.index, name:e.name, table:e.table, priority:e.priority });
    }
    return { version:1, kind, source:record.source, identity:record.identity, revision:record.revision,
        url:record.url, user_agent:record.user_agent, hwid:record.hwid, entries };
}
function read_generation(dir, source, generation) {
    if (type(dir) != 'string' || dir == '' || dir == '/' || !source_ok(source) || !hash_ok(generation)) return null;
    let path = dir + '/' + source + '-' + generation + '.json';
    if (digest(path) != generation) return null;
    let data = fs.readfile(path), record;
    if (type(data) != 'string' || length(data) > 32768) return null;
    try { record = checked(json(data)); } catch (e) { return null; }
    if (record == null || record.source != source || digest(path) != generation) return null;
    return record;
}
function current_id(dir, source) {
    if (type(dir) != 'string' || dir == '' || dir == '/' || !source_ok(source)) return null;
    let data = fs.readfile(dir + '/' + source + '.current');
    if (type(data) != 'string') return null;
    let value = trim(data);
    return hash_ok(value) ? value : null;
}
function stage(dir, good_dir, record, verify) {
    let value = checked(record);
    if (value == null || type(verify) != 'function' || type(good_dir) != 'string' || good_dir == '' || good_dir == '/' ||
        !common.secure_private_dir(dir)) return null;
    if ((value.kind == 'subscription' && identity.calculate(dir, value.source, value.url, value.user_agent, value.hwid) != value.identity) ||
        store.revision(good_dir + '/' + value.revision, value.source, value.identity) != value.revision) return null;
    for (let entry in value.entries) try { if (verify(entry) !== true) return null; } catch (e) { return null; }
    let t = clock(), tmp = sprintf('%s/.generation-%s-%d-%d.tmp', dir, value.source, t[0], t[1]);
    if (common.write_private_json_file(tmp, value) == null) { fs.unlink(tmp); return null; }
    let hash = digest(tmp);
    if (hash == null || !fs.rename(tmp, dir + '/' + value.source + '-' + hash + '.json')) { fs.unlink(tmp); return null; }
    return hash;
}
// expected may be null for a first generation. A failed compare leaves the old
// pointer untouched. It is not a CAS against non-cooperating external writers.
function switch_to(dir, source, expected, generation) {
    if (!source_ok(source) || !hash_ok(generation) || (expected != null && !hash_ok(expected)) ||
        (expected == null && fs.stat(dir + '/' + source + '.current') != null) ||
        current_id(dir, source) != expected || read_generation(dir, source, generation) == null) return false;
    let t = clock(), tmp = sprintf('%s/.pointer-%s-%d-%d.tmp', dir, source, t[0], t[1]);
    if (common.write_private_file(tmp, generation + '\n') == null) { fs.unlink(tmp); return false; }
    if (current_id(dir, source) != expected || !fs.rename(tmp, dir + '/' + source + '.current')) { fs.unlink(tmp); return false; }
    return true;
}
// Only used when undoing a just-created generation under the same locks.
function remove_current(dir, source, expected) {
    if (!source_ok(source) || !hash_ok(expected) || current_id(dir, source) != expected) return false;
    return fs.unlink(dir + '/' + source + '.current') === true;
}
return { stage, read_generation, current_id, switch_to, remove_current };
