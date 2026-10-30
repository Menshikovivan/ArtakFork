// Read-only checks used by the locked lifecycle swap factory. No config or
// credentials are returned to the caller, command line, or logs.
let fs = require('fs');
let uci = require('uci');
let sources = require('subscription.amnezia_snapshot_sources');
let generation = require('subscription.amnezia_generation');
let restore = require('subscription.amnezia_generation_restore');
let snapshot = require('subscription.amnezia_snapshot');
function current_rule(source, identity, dirs, opts) {
    opts = type(opts) == 'object' ? opts : {};
    try {
        let c = type(opts.cursor) == 'function' ? opts.cursor() : uci.cursor();
        let collect = type(opts.collect) == 'function' ? opts.collect : sources.collect;
        let all = collect(c, dirs), matches = 0;
        if (type(all) != 'array') return false;
        for (let item in all) if (item.source == source && item.identity == identity) matches++;
        return matches == 1;
    } catch (e) { return false; }
}
function verify_generation(source, identity, id, dirs, snapshot_dir, config_path, opts) {
    opts = type(opts) == 'object' ? opts : {};
    try {
        let current = type(opts.current_id) == 'function' ? opts.current_id : generation.current_id;
        let reader = type(opts.read_config) == 'function' ? opts.read_config : fs.readfile;
        let restore_generation = type(opts.restore) == 'function' ? opts.restore : restore.restore;
        let load_snapshot = type(opts.snapshot) == 'function' ? opts.snapshot : snapshot.load;
        if (!current_rule(source, identity, dirs, opts) || current(dirs.generation, source) != id) return false;
        let cursor = type(opts.cursor) == 'function' ? opts.cursor() : uci.cursor();
        if (!cursor || cursor.load('network') == null) return false;
        let restored = restore_generation(dirs.generation, dirs.good, source, cursor, 3000,
            { matches_source:function() { return current_rule(source, identity, dirs, opts); } });
        let expected = load_snapshot(snapshot_dir), data = reader(config_path), config;
        if (type(restored) != 'object' || restored.generation != id || restored.identity != identity ||
            type(expected) != 'object' || type(data) != 'string' || length(data) > 16777216) return false;
        try { config = json(data); } catch (ignored) { return false; }
        if (type(config?.outbounds) != 'array') return false;
        let matched = 0;
        for (let entry in expected.entries) {
            if (entry.source != source) continue;
            let count = 0;
            for (let out in config.outbounds)
                if (out.type == 'direct' && out.bind_interface == entry.name && int(out.routing_mark) == entry.mark) count++;
            if (count != 1 || entry.identity != identity || entry.revision != restored.revision) return false;
            matched++;
        }
        return matched == length(restored.entries) && matched > 0 &&
            current(dirs.generation, source) == id && current_rule(source, identity, dirs, opts);
    } catch (e) { return false; }
}
return { current_rule, verify_generation };
