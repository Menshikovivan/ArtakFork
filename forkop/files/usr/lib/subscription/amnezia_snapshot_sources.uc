// Gather the complete set of enabled AWG sources from the same UCI snapshot
// used by sing-box. Legacy sources must already have been migrated under locks.
let fs = require('fs');
let common = require('core.common');
let connections = require('config.connections');
let subscription = require('singbox.subscription');
let manual = require('subscription.amnezia_manual_source');
let generation = require('subscription.amnezia_generation');
let snapshot = require('subscription.amnezia_snapshot');
let publish = require('subscription.amnezia_snapshot_publish');
function collect(cursor, dirs) {
    if (!cursor || type(dirs) != 'object') return null;
    let sources = [], seen = {}, invalid = false;
    try {
        if (cursor.load('forkop') == null) return null;
        connections.set_item_sections_from_cursor(cursor, 'forkop');
        cursor.foreach('forkop', 'section', function(section) {
            if (invalid || !common.bool_option(section, 'enabled', true)) return;
            let m = manual.from_id(section.manual_awg_id);
            if (m != null) {
                let present = fs.stat(dirs.generation + '/' + m.source + '.current') != null;
                if (!present && fs.stat(dirs.active + '/' + m.source + '.json') != null) { invalid = true; return; }
                if (present) {
                    if (seen[m.source]) { invalid = true; return; }
                    seen[m.source] = true; push(sources, m);
                }
            }
            let urls = connections.subscription_urls(section);
            for (let i = 0; i < length(urls); i++) {
                let source = subscription.source_id(section['.name'], i + 1);
                let present = fs.stat(dirs.generation + '/' + source + '.current') != null;
                if (!present && fs.stat(dirs.active + '/' + source + '.json') != null) { invalid = true; return; }
                if (!present) continue;
                let id = subscription.awg_source_identity(source, urls[i], connections.subscription_user_agent(section, urls[i]),
                    connections.subscription_hwid(section, urls[i]), dirs.candidate);
                if (id == null || seen[source]) { invalid = true; return; }
                seen[source] = true; push(sources, {source,identity:id});
            }
        });
    } catch (e) { return null; }
    return invalid ? null : sources;
}
// temp_old and temp_new are trusted private work dirs. The selected new
// generation is inspected without changing any active pointer.
function build_pair(cursor, dirs, source, identity, old_id, new_id, occupied_marks, timeout_ms) {
    let sources = collect(cursor, dirs);
    if (type(sources) != 'array' || generation.current_id(dirs.generation, source) != old_id) return null;
    let next = [], matched = 0;
    for (let entry in sources) {
        if (entry.source == source) {
            if (entry.identity != identity) return null;
            push(next, {source,identity,generation:new_id,expected_current:old_id}); matched++;
        } else push(next, entry);
    }
    if (matched != 1) return null;
    let opts = {generation_dir:dirs.generation};
    let old_snapshot = snapshot.build(dirs.temp_old, dirs.good, dirs.active, sources, cursor, timeout_ms, occupied_marks, opts);
    if (old_snapshot == null) return null;
    let new_snapshot = snapshot.build(dirs.temp_new, dirs.good, dirs.active, next, cursor, timeout_ms, occupied_marks, opts);
    if (new_snapshot == null || generation.current_id(dirs.generation, source) != old_id) return null;
    let old_sha = publish.publish(dirs.temp_old, dirs.snapshot_base), new_sha = publish.publish(dirs.temp_new, dirs.snapshot_base);
    if (old_sha == null || new_sha == null || generation.current_id(dirs.generation, source) != old_id) return null;
    return {old:old_sha, new:new_sha};
}
return { collect, build_pair };
