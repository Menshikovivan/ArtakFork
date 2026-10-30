// A single secret-free snapshot, shared by firewall and generator. Callers hold
// lifecycle locks throughout construction, use and replacement of this file.
let fs = require('fs');
let common = require('core.common');
let guard = require('subscription.amnezia_guard_plan');
function digest(path) {
    let quoted = "'" + replace(path, /'/g, "'\\''") + "'";
    let pipe = fs.popen('sha256sum ' + quoted + ' 2>/dev/null', 'r');
    if (!pipe) return null;
    let output = pipe.read('all'), status = pipe.close();
    if (status != 0 || type(output) != 'string') return null;
    let hash = split(trim(output), /[ \t\r\n]+/)[0];
    return match(hash, /^[0-9a-f]{64}$/) ? hash : null;
}
function clean(entries) {
    if (type(entries) != 'array' || length(entries) > 32) return null;
    let p = guard.plan(entries, [], 0x08000000);
    if (!p.ok) return null;
    let result = [], sources = {}, priorities = {};
    for (let i = 0; i < length(entries); i++) {
        let e = entries[i];
        if (type(e.source) != 'string' || !match(e.source, /^[A-Za-z0-9_-]{1,100}$/) ||
            type(e.identity) != 'string' || !match(e.identity, /^[0-9a-f]{64}$/) ||
            type(e.revision) != 'string' || !match(e.revision, /^[0-9a-f]{64}$/) ||
            type(e.index) != 'int' || e.index < 0 || e.index >= 32 || e.mark != p.guards[i].mark)
            return null;
        let source_index = e.source + ':' + e.index, priority = +e.priority;
        if (sources[source_index] || priorities['' + priority] || priorities['' + (priority + 1)]) return null;
        sources[source_index] = true; priorities['' + priority] = true; priorities['' + (priority + 1)] = true;
        push(result, { index: e.index, name: e.name, table: e.table, priority: e.priority,
            mark: e.mark, source: e.source, identity: e.identity, revision: e.revision });
    }
    return result;
}
function save(dir, entries) {
    if (type(dir) != 'string' || dir == '' || dir == '/') return null;
    let values = clean(entries);
    if (values == null || !common.secure_private_dir(dir)) return null;
    let t = clock(), tmp = sprintf('%s/.snapshot-%d-%d.tmp', dir, t[0], t[1]);
    if (common.write_private_json_file(tmp, { version: 1, entries: values }) == null) { fs.unlink(tmp); return null; }
    let revision = digest(tmp);
    if (revision == null || !fs.rename(tmp, dir + '/snapshot.json')) { fs.unlink(tmp); return null; }
    return { revision, entries: values };
}
function load(dir) {
    if (type(dir) != 'string' || dir == '' || dir == '/') return null;
    let path = dir + '/snapshot.json', revision = digest(path), data = fs.readfile(path);
    if (revision == null || type(data) != 'string' || length(data) > 32768) return null;
    let record; try { record = json(data); } catch (e) { return null; }
    if (type(record) != 'object' || record.version != 1) return null;
    let entries = clean(record.entries);
    if (entries == null || digest(path) != revision) return null;
    return { revision, entries };
}
// Each source identity must already be derived from current subscription
// settings. Lifecycle owns global locks and mark collision checks.
function build(dir, candidate_dir, active_dir, sources, cursor, timeout_ms, occupied_marks, opts) {
    if (type(sources) != 'array' || length(sources) > 32 || type(occupied_marks) != 'array') return null;
    opts = type(opts) == 'object' ? opts : {};
    let generation_dir = opts.generation_dir || getenv('FORKOP_AWG_GENERATION_DIR') || '/etc/forkop/awg-generations';
    let gen = require('subscription.amnezia_generation');
    let restore = type(opts.restore_generation) == 'function' ? opts.restore_generation : require('subscription.amnezia_generation_restore').restore;
    let inspect = type(opts.inspect_generation) == 'function' ? opts.inspect_generation : require('subscription.amnezia_generation_restore').inspect;
    let current_generation = type(opts.current_generation) == 'function' ? opts.current_generation : gen.current_id;
    let entries = [], seen = {};
    for (let s in sources) {
        if (type(s) != 'object' || type(s.source) != 'string' || seen[s.source]) return null;
        seen[s.source] = true;
        let before = current_generation(generation_dir, s.source);
        if (s.generation != null && (type(s.expected_current) != 'string' || before != s.expected_current)) return null;
        let restored = s.generation != null
            ? inspect(generation_dir, candidate_dir, s.source, s.generation, cursor, timeout_ms, { matches_source: function() { return true; } })
            : restore(generation_dir, candidate_dir, s.source, cursor, timeout_ms, { matches_source: function() { return true; } });
        if (type(restored) != 'object' || restored.identity != s.identity || type(restored.entries) != 'array') return null;
        let revision = restored.revision;
        for (let e in restored.entries)
            push(entries, { index: e.index, name: e.name, table: e.table, priority: e.priority,
                source: s.source, identity: s.identity, revision });
        if (current_generation(generation_dir, s.source) != before || (s.generation == null && before != restored.generation)) return null;
    }
    let planned = guard.plan(entries, occupied_marks, 0x08000000);
    if (!planned.ok) return null;
    for (let i = 0; i < length(entries); i++) entries[i].mark = planned.guards[i].mark;
    return save(dir, entries);
}
return { save, load, build };
