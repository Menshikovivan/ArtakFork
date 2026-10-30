// Private immutable normalized legacy subscription data. It may contain
// VLESS credentials and must never be logged or emitted as metadata.
let fs = require('fs');
let common = require('core.common');
let generation = require('subscription.amnezia_generation');
function valid_hash(s) { return type(s) == 'string' && match(s, /^[0-9a-f]{64}$/) != null; }
function path(dir, revision) {
    if (type(dir) != 'string' || dir == '' || dir == '/' || !valid_hash(revision)) return null;
    let file = dir + '/' + revision + '.json';
    return generation.hash_file(file) == revision ? file : null;
}
function put(source_path, dir) {
    if (type(source_path) != 'string' || type(dir) != 'string' || dir == '' || dir == '/') return null;
    if (!require('subscription.parser').validate_subscription(source_path)) return null;
    let st = fs.lstat(dir);
    if (st != null && st.type != 'directory') return null;
    let revision = generation.hash_file(source_path), data = fs.readfile(source_path);
    if (revision == null || type(data) != 'string' || length(data) > 1048576 || !common.secure_private_dir(dir)) return null;
    if (path(dir, revision) != null) return revision;
    let t = clock(), tmp = sprintf('%s/.legacy-%d-%d.tmp', dir, t[0], t[1]);
    if (common.write_private_file(tmp, data) == null) { fs.unlink(tmp); return null; }
    if (generation.hash_file(tmp) != revision || generation.hash_file(source_path) != revision ||
        !fs.rename(tmp, dir + '/' + revision + '.json')) { fs.unlink(tmp); return null; }
    return path(dir, revision) != null ? revision : null;
}
return { put, path };
