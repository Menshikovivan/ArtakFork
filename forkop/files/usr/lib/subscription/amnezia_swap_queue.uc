// Private request metadata only: no URL or keys. Writers own the subscription
// lock; the worker reacquires reload -> subscription -> AWG locks, rechecks
// current source and candidate and only then starts the journaled swap.
let fs = require('fs');
let common = require('core.common');
function source_ok(s) { return type(s) == 'string' && match(s, /^[A-Za-z0-9_-]{1,100}$/) != null; }
function hash_ok(s) { return type(s) == 'string' && match(s, /^[0-9a-f]{64}$/) != null; }
function read(dir, source) {
    if (type(dir) != 'string' || dir == '' || dir == '/' || !source_ok(source)) return null;
    let data = fs.readfile(dir + '/' + source + '.request.json'), r;
    if (type(data) != 'string' || length(data) > 2048) return null;
    try { r = json(data); } catch (e) { return null; }
    if (type(r) != 'object' || r.version != 1 || r.source != source ||
        !hash_ok(r.identity) || !hash_ok(r.revision) || !hash_ok(r.old_generation) ||
        (r.mode != 'only' && r.mode != 'mixed') || (r.mode == 'mixed' && !hash_ok(r.legacy_revision))) return null;
    let result = { version:1, source, identity:r.identity, revision:r.revision, old_generation:r.old_generation, mode:r.mode };
    if (r.mode == 'mixed') result.legacy_revision = r.legacy_revision;
    return result;
}
function enqueue(dir, source, identity, revision, old_generation, mode, legacy_revision) {
    mode = mode || 'only';
    if (type(dir) != 'string' || dir == '' || dir == '/' || !source_ok(source) ||
        !hash_ok(identity) || !hash_ok(revision) || !hash_ok(old_generation) ||
        (mode != 'only' && mode != 'mixed') || (mode == 'mixed' && !hash_ok(legacy_revision)) || !common.secure_private_dir(dir)) return false;
    let t = clock(), tmp = sprintf('%s/.queue-%s-%d-%d.tmp', dir, source, t[0], t[1]);
    let request = {version:1, source, identity, revision, old_generation, mode};
    if (mode == 'mixed') request.legacy_revision = legacy_revision;
    if (common.write_private_json_file(tmp, request) == null) { fs.unlink(tmp); return false; }
    if (!fs.rename(tmp, dir + '/' + source + '.request.json')) { fs.unlink(tmp); return false; }
    return true;
}
function remove(dir, expected) {
    if (type(expected) != 'object' || !source_ok(expected.source)) return false;
    let current = read(dir, expected.source);
    if (current == null || sprintf('%J', current) != sprintf('%J', expected)) return false;
    return fs.unlink(dir + '/' + expected.source + '.request.json') === true;
}
return { enqueue, read, remove };
