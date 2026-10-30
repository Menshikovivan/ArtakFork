// Durable, secret-free swap journal. Caller owns all lifecycle locks and must
// verify old/new live state and firewall before acting on the recovery plan.
let fs = require('fs');
let common = require('core.common');
let generation = require('subscription.amnezia_generation');
let phases = ['prepared', 'union', 'published', 'verified', 'retired'];
function hash_ok(s) { return type(s) == 'string' && match(s, /^[0-9a-f]{64}$/) != null; }
function source_ok(s) { return type(s) == 'string' && match(s, /^[A-Za-z0-9_-]{1,100}$/) != null; }
function read(dir, source) {
    if (type(dir) != 'string' || dir == '' || dir == '/' || !source_ok(source)) return null;
    let data = fs.readfile(dir + '/' + source + '.swap.json'), r;
    if (type(data) != 'string' || length(data) > 4096) return null;
    try { r = json(data); } catch (e) { return null; }
    if (type(r) != 'object' || r.version != 1 || r.source != source || !hash_ok(r.old_generation) ||
        !hash_ok(r.new_generation) || r.old_generation == r.new_generation || index(phases, r.phase) < 0) return null;
    if ((r.old_snapshot != null || r.new_snapshot != null) && (!hash_ok(r.old_snapshot) || !hash_ok(r.new_snapshot))) return null;
    if (r.phase != 'prepared' && (!hash_ok(r.old_snapshot) || !hash_ok(r.new_snapshot))) return null;
    return { version:1, source, old_generation:r.old_generation, new_generation:r.new_generation,
        old_snapshot:r.old_snapshot, new_snapshot:r.new_snapshot, phase:r.phase };
}
function write(dir, source, old_id, new_id, phase) {
    if (type(dir) != 'string' || dir == '' || dir == '/' || !source_ok(source) || !hash_ok(old_id) || !hash_ok(new_id) ||
        old_id == new_id || index(phases, phase) < 0 || !common.secure_private_dir(dir)) return false;
    let path = dir + '/' + source + '.swap.json', prior = read(dir, source);
    if (prior == null && fs.stat(path) != null) return false;
    if (prior == null && phase != 'prepared') return false;
    if (prior != null && (prior.old_generation != old_id || prior.new_generation != new_id ||
        index(phases, phase) != index(phases, prior.phase) + 1)) return false;
    if (phase != 'prepared' && (prior == null || !hash_ok(prior.old_snapshot) || !hash_ok(prior.new_snapshot))) return false;
    let t = clock(), tmp = sprintf('%s/.journal-%s-%d-%d.tmp', dir, source, t[0], t[1]);
    let record = { version:1, source, old_generation:old_id, new_generation:new_id, phase };
    if (prior != null && prior.old_snapshot != null) { record.old_snapshot = prior.old_snapshot; record.new_snapshot = prior.new_snapshot; }
    if (common.write_private_json_file(tmp, record) == null) { fs.unlink(tmp); return false; }
    if (!fs.rename(tmp, path)) { fs.unlink(tmp); return false; }
    return true;
}
function bind_snapshots(dir, source, old_id, new_id, old_snapshot, new_snapshot) {
    let prior = read(dir, source);
    if (prior == null || prior.phase != 'prepared' || prior.old_generation != old_id || prior.new_generation != new_id ||
        prior.old_snapshot != null || !hash_ok(old_snapshot) || !hash_ok(new_snapshot)) return false;
    let t = clock(), tmp = sprintf('%s/.journal-%s-%d-%d.tmp', dir, source, t[0], t[1]);
    let record = { version:1, source, old_generation:old_id, new_generation:new_id, old_snapshot, new_snapshot, phase:'prepared' };
    if (common.write_private_json_file(tmp, record) == null) { fs.unlink(tmp); return false; }
    if (!fs.rename(tmp, dir + '/' + source + '.swap.json')) { fs.unlink(tmp); return false; }
    return true;
}
function recovery(dir, generation_dir, source) {
    let journal = read(dir, source);
    if (journal == null) return null;
    let current = generation.current_id(generation_dir, source);
    if (current != journal.old_generation && current != journal.new_generation)
        return { action:'inspect' };
    if ((journal.phase == 'verified' || journal.phase == 'retired') && current == journal.new_generation)
        return { action:'finish', generation:current };
    return { action:'restore', generation:journal.old_generation };
}
// Caller supplies a final live-state check under the same lifecycle locks.
function clear(dir, source, old_id, new_id, verify) {
    let prior = read(dir, source);
    if (prior == null || prior.old_generation != old_id || prior.new_generation != new_id || type(verify) != 'function') return false;
    try { if (verify() !== true) return false; } catch (e) { return false; }
    return fs.unlink(dir + '/' + source + '.swap.json') === true;
}
return { read, write, bind_snapshots, recovery, clear };
