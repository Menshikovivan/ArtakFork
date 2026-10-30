// Persistent, secret-free mapping for already applied AWG interfaces. Reading
// it after restart never implies readiness: the caller MUST supply a verifier
// that checks the current interface, matching configuration, live kernel rules
// and a recent handshake. This module itself never starts interfaces or
// publishes them to sing-box. Use a dedicated root-owned private directory.
let fs = require('fs');
let common = require('core.common');
let routes = require('subscription.amnezia_routes');

function safe_source(s) { return type(s) == 'string' && match(s, /^[A-Za-z0-9_-]{1,100}$/) != null; }
function safe_hash(s) { return type(s) == 'string' && match(s, /^[0-9a-f]{64}$/) != null; }

function checked(entries, verify) {
    if (type(entries) != 'array' || !length(entries) || length(entries) > 32 || type(verify) != 'function')
        return null;
    let clean = [], names = {}, tables = {}, priorities = {}, indices = {};
    for (let e in entries) {
        if (type(e) != 'object' || type(e.index) != 'int' || e.index < 0 || e.index >= 32 ||
            !routes.prepare(e.name, e.table, e.priority, true, false).ok)
            return null;
        let priority = +e.priority;
        if (names[e.name] || tables[e.table] || indices['' + e.index] ||
            priorities['' + priority] || priorities['' + (priority + 1)]) return null;
        names[e.name] = true; tables[e.table] = true; indices['' + e.index] = true;
        priorities['' + priority] = true; priorities['' + (priority + 1)] = true;
        // Discard every other field, including accidentally supplied keys.
        let item = { index: e.index, name: e.name, table: e.table, priority: e.priority };
        try { if (verify(item) !== true) return null; } catch (err) { return null; }
        push(clean, item);
    }
    return clean;
}

function save(dir, source, identity, revision, entries, verify) {
    if (type(dir) != 'string' || dir == '' || dir == '/' || !safe_source(source) ||
        !safe_hash(identity) || !safe_hash(revision)) return false;
    let clean = checked(entries, verify);
    if (clean == null || !common.secure_private_dir(dir)) return false;
    let stamp = clock();
    let tmp = sprintf('%s/.%s.%d.%d.tmp', dir, source, stamp[0], stamp[1]);
    let target = dir + '/' + source + '.json';
    let record = { version: 1, source, identity, revision, entries: clean };
    if (common.write_private_json_file(tmp, record) == null) { fs.unlink(tmp); return false; }
    if (!fs.rename(tmp, target)) { fs.unlink(tmp); return false; }
    return true;
}

function restore(dir, source, identity, revision, verify) {
    if (type(dir) != 'string' || dir == '' || !safe_source(source) || !safe_hash(identity) || !safe_hash(revision))
        return null;
    let data = fs.readfile(dir + '/' + source + '.json');
    if (data == null || length(data) > 16384) return null;
    let record;
    try { record = json(data); } catch (err) { return null; }
    if (type(record) != 'object' || record.version != 1 || record.source != source ||
        record.identity != identity || record.revision != revision) return null;
    return checked(record.entries, verify);
}

// This only selects a candidate immutable revision. It does not establish
// readiness; restore() must still validate every entry with a live verifier.
function peek(dir, source, identity) {
    if (type(dir) != 'string' || dir == '' || !safe_source(source) || !safe_hash(identity)) return null;
    let data = fs.readfile(dir + '/' + source + '.json');
    if (type(data) != 'string' || length(data) > 16384) return null;
    let record; try { record = json(data); } catch (e) { return null; }
    if (type(record) != 'object' || record.version != 1 || record.source != source ||
        record.identity != identity || !safe_hash(record.revision)) return null;
    return record.revision;
}

return { save, restore, peek };
