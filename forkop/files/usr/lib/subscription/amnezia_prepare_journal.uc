// Write the complete reservation plan before the first new UCI commit. The
// in-flight checkpoint is saved BEFORE each apply; after a crash, an in-flight
// operation is uncertain and must be inspected, never assumed absent.
// Caller owns reload, subscription and AWG locks throughout each transaction.
let fs = require('fs');
let common = require('core.common');
let generation = require('subscription.amnezia_generation');
let store = require('subscription.amnezia_store');
let routes = require('subscription.amnezia_routes');
function source_ok(s) { return type(s) == 'string' && match(s, /^[A-Za-z0-9_-]{1,100}$/) != null; }
function hash_ok(s) { return type(s) == 'string' && match(s, /^[0-9a-f]{64}$/) != null; }
function validate(r, source) {
    if (type(r) != 'object' || r.version != 1 || r.source != source || !source_ok(source) ||
        !hash_ok(r.old_generation) || !hash_ok(r.identity) || !hash_ok(r.revision) ||
        type(r.entries) != 'array' || !length(r.entries) || length(r.entries) > 32 ||
        type(r.completed) != 'int' || r.completed < 0 || r.completed > length(r.entries) ||
        (r.inflight != null && (type(r.inflight) != 'int' || r.inflight != r.completed || r.inflight >= length(r.entries)))) return null;
    let clean = [], names = {}, tables = {}, priorities = {};
    for (let i = 0; i < length(r.entries); i++) {
        let e = r.entries[i];
        if (type(e) != 'object' || e.index != i || !routes.prepare(e.name, e.table, e.priority, true, false).ok) return null;
        let p = int(e.priority);
        if (names[e.name] || tables[e.table] || priorities['' + p] || priorities['' + (p + 1)]) return null;
        names[e.name] = true; tables[e.table] = true; priorities['' + p] = true; priorities['' + (p + 1)] = true;
        push(clean, { index:i, name:e.name, table:e.table, priority:e.priority });
    }
    return {version:1, source, old_generation:r.old_generation, identity:r.identity, revision:r.revision,
        entries:clean, completed:r.completed, inflight:r.inflight};
}
function read(dir, source) {
    if (type(dir) != 'string' || dir == '' || dir == '/' || !source_ok(source)) return null;
    let data = fs.readfile(dir + '/' + source + '.prepare.json'), record;
    if (type(data) != 'string' || length(data) > 16384) return null;
    try { record = validate(json(data), source); } catch (e) { return null; }
    return record;
}
function persist(dir, record) {
    let t = clock(), tmp = sprintf('%s/.prepare-%s-%d-%d.tmp', dir, record.source, t[0], t[1]);
    if (common.write_private_json_file(tmp, record) == null) { fs.unlink(tmp); return false; }
    if (!fs.rename(tmp, dir + '/' + record.source + '.prepare.json')) { fs.unlink(tmp); return false; }
    return true;
}
function create(dir, generation_dir, candidate_dir, good_dir, source, old_generation, identity, revision, entries) {
    let old = generation.read_generation(generation_dir, source, old_generation);
    if (type(dir) != 'string' || dir == '' || dir == '/' || !source_ok(source) ||
        fs.stat(dir + '/' + source + '.prepare.json') != null ||
        generation.current_id(generation_dir, source) != old_generation ||
        old == null || old.identity != identity || old.revision == revision ||
        store.revision(candidate_dir, source, identity) != revision) return false;
    let profiles = store.load_configs(candidate_dir, source, identity);
    let record = validate({ version:1, source, old_generation, identity, revision, entries, completed:0, inflight:null }, source);
    if (record == null || type(profiles) != 'array' || length(profiles) != length(record.entries) || !common.secure_private_dir(dir) ||
        !store.promote(candidate_dir, good_dir, source, identity, revision)) return false;
    if (generation.current_id(generation_dir, source) != old_generation || store.revision(candidate_dir, source, identity) != revision ||
        store.revision(good_dir + '/' + revision, source, identity) != revision || fs.stat(dir + '/' + source + '.prepare.json') != null) return false;
    return persist(dir, record);
}
function begin(dir, source, index) {
    let r = read(dir, source);
    if (r == null || r.inflight != null || type(index) != 'int' || index != r.completed || index >= length(r.entries)) return false;
    r.inflight = index;
    return persist(dir, r);
}
function finish(dir, source, index) {
    let r = read(dir, source);
    if (r == null || type(index) != 'int' || r.inflight == null || r.inflight != index || r.completed != index) return false;
    r.completed++; r.inflight = null;
    return persist(dir, r);
}
// Reserves a full plan logically while caller holds all transition locks. Each
// apply must still recheck the actual kernel/UCI allocation before committing.
function reserve(dir, generation_dir, candidate_dir, good_dir, source, old_generation, identity, cursor, opts) {
    opts = type(opts) == 'object' ? opts : {};
    let revision = store.revision(candidate_dir, source, identity);
    let profiles = store.load_configs(candidate_dir, source, identity);
    if (revision == null || type(profiles) != 'array' || !length(profiles)) return null;
    let choose = type(opts.choose_many) == 'function' ? opts.choose_many : require('subscription.amnezia_allocate').choose_many;
    let selected;
    try { selected = choose(cursor, length(profiles), opts); } catch (e) { return null; }
    if (type(selected) != 'object' || selected.ok !== true || type(selected.allocations) != 'array' || length(selected.allocations) != length(profiles)) return null;
    let entries = [];
    for (let i = 0; i < length(selected.allocations); i++) {
        let a = selected.allocations[i];
        if (type(a) != 'object') return null;
        push(entries, { index:i, name:a.name, table:a.table, priority:a.priority });
    }
    if (!create(dir, generation_dir, candidate_dir, good_dir, source, old_generation, identity, revision, entries)) return null;
    return read(dir, source);
}
// Publish the swap journal before removing this one, so a crash can leave both
// journals but never neither. A double-journal state is deliberately blocked
// pending reconciliation; callers must keep all transition locks held.
function handoff(dir, swap_dir, generation_dir, source, new_generation) {
    let plan = read(dir, source), gen = generation.read_generation(generation_dir, source, new_generation);
    if (plan == null || plan.inflight != null || plan.completed != length(plan.entries) || gen == null ||
        gen.identity != plan.identity || gen.revision != plan.revision ||
        generation.current_id(generation_dir, source) != plan.old_generation ||
        sprintf('%J', gen.entries) != sprintf('%J', plan.entries)) return false;
    let swaps = require('subscription.amnezia_swap_journal');
    if (!swaps.write(swap_dir, source, plan.old_generation, new_generation, 'prepared')) return false;
    let persisted = swaps.read(swap_dir, source);
    if (persisted == null || persisted.old_generation != plan.old_generation || persisted.new_generation != new_generation ||
        persisted.phase != 'prepared' || generation.current_id(generation_dir, source) != plan.old_generation) return false;
    return fs.unlink(dir + '/' + source + '.prepare.json') === true;
}
return { create, read, begin, finish, reserve, handoff };
