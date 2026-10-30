// Recovery orchestration only. The caller must own subscription, reload,
// network and firewall lifecycle locks and supply trusted real runtime ops.
// This module does not install guards or construct those ops itself.
let fs = require('fs');
let swap = require('subscription.amnezia_swap');
function missing_path(path, depth) {
    if (depth > 8 || type(path) != 'string' || path == '' || path == '/') return false;
    let parts = match(path, /^(.*)\/([^\/]+)$/);
    if (parts == null || parts[1] == '' || parts[2] == '.' || parts[2] == '..') return false;
    let parent = fs.lstat(parts[1]);
    if (parent == null) return missing_path(parts[1], depth + 1);
    if (parent.type != 'directory') return false;
    let siblings = fs.lsdir(parts[1]);
    return type(siblings) == 'array' && index(siblings, parts[2]) < 0;
}
function recover_all(journal_dir, generation_dir, opts) {
    opts = type(opts) == 'object' ? opts : {};
    if (type(journal_dir) != 'string' || journal_dir == '' || journal_dir == '/' ||
        type(generation_dir) != 'string' || generation_dir == '' || generation_dir == '/' ||
        type(opts.holds_locks) != 'function')
        return {ok:false,error:'Recovery requires lifecycle locks'};
    try {
        if (opts.holds_locks() !== true) return {ok:false,error:'Lifecycle locks not held'};
        let stat = fs.lstat(journal_dir);
        if (stat == null) {
            // Distinguish a genuinely absent directory from unreadable state.
            if (!missing_path(journal_dir, 0))
                return {ok:false,error:'Cannot inspect swap journals'};
            return {ok:true,recovered:0};
        }
        if (stat.type != 'directory') return {ok:false,error:'Invalid swap journal directory'};
        let entries = fs.lsdir(journal_dir);
        if (type(entries) != 'array') return {ok:false,error:'Cannot inspect swap journals'};
        let sources = [];
        for (let filename in sort(entries)) {
            if (!match(filename, /\.swap\.json$/)) continue;
            let matched = match(filename, /^([A-Za-z0-9_-]{1,100})\.swap\.json$/);
            if (matched == null) return {ok:false,error:'Invalid swap journal filename'};
            push(sources, matched[1]);
        }
        let recover = type(opts.recover) == 'function' ? opts.recover : swap.recover;
        for (let source in sources) {
            if (opts.holds_locks() !== true) return {ok:false,error:'Lifecycle locks lost'};
            if (type(opts.ops_for_source) != 'function') return {ok:false,error:'Recovery operations unavailable'};
            let operations = opts.ops_for_source(source);
            if (type(operations) != 'object') return {ok:false,error:'Recovery operations unavailable'};
            let result = recover(operations, journal_dir, generation_dir, source);
            if (type(result) != 'object' || result.ok !== true || fs.lstat(journal_dir + '/' + source + '.swap.json') != null)
                return {ok:false,error:'Swap recovery requires inspection'};
        }
        if (opts.holds_locks() !== true) return {ok:false,error:'Lifecycle locks lost'};
        // Do not claim success if another journal appeared during recovery.
        let remaining = fs.lsdir(journal_dir);
        if (type(remaining) != 'array') return {ok:false,error:'Cannot inspect swap journals'};
        for (let filename in remaining)
            if (match(filename, /\.swap\.json$/)) return {ok:false,error:'Swap journal appeared during recovery'};
        return {ok:true,recovered:length(sources)};
    } catch (e) { return {ok:false,error:'Swap recovery failed'}; }
}
return { recover_all };
