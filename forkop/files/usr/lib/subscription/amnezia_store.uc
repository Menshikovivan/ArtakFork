// Private, single-file last-known-good storage in a dedicated AWG directory
// (never the existing subscription cache). Callers must hold the existing
// subscription and reload locks and may only publish after runtime validation.
// The identity is a caller-computed SHA-256 of source URL + UA + HWID; never
// expose that input or the profile contents via logs or UI.
let fs = require('fs');
let common = require('core.common');
let parser = require('subscription.amnezia_conf');

function source_ok(source) {
    return type(source) == 'string' && match(source, /^[a-zA-Z0-9_-]{1,100}$/) != null;
}
function identity_ok(identity) {
    return type(identity) == 'string' && match(identity, /^[0-9a-f]{64}$/) != null;
}

// Internal use only. Each result contains credentials and must not be logged.
function load_configs(dir, source, identity) {
    if (!source_ok(source) || !identity_ok(identity)) return null;
    let content = fs.readfile(dir + '/' + source + '.awg.json');
    if (content == null || length(content) > 1048576) return null;
    let record;
    try { record = json(content); } catch (e) { return null; }
    if (type(record) != 'object' || record.version != 1 || record.identity != identity ||
        type(record.configs) != 'array' || !length(record.configs) || length(record.configs) > 32) return null;
    for (let config in record.configs) {
        let parsed = parser.parse_conf(config);
        if (!parsed.ok || length(parsed.peers) != 1) return null;
    }
    return record.configs;
}

function load(dir, source, identity) {
    let configs = load_configs(dir, source, identity);
    if (configs == null) return null;
    return map(configs, config => parser.parse_conf(config));
}

// Hash the private file by pathname only; credentials never enter argv or logs.
// The caller must hold the subscription lock across revision and use.
function revision(dir, source, identity) {
    if (type(dir) != 'string' || dir == '' || dir == '/' || load_configs(dir, source, identity) == null)
        return null;
    let path = dir + '/' + source + '.awg.json';
    let quoted = "'" + replace(path, /'/g, "'\\''") + "'";
    let pipe = fs.popen('sha256sum ' + quoted + ' 2>/dev/null', 'r');
    if (!pipe) return null;
    let output = pipe.read('all');
    let status = pipe.close();
    if (status != 0 || type(output) != 'string') return null;
    let digest = split(trim(output), /[ \t\r\n]+/)[0];
    return identity_ok(digest) ? digest : null;
}

// Store immutable last-good bytes under their digest. Publishing a new manifest
// is a separate atomic step, so a failed publication never destroys the old
// revision. Caller holds subscription/lifecycle locks throughout promotion.
function promote(dir, last_good_dir, source, identity, expected) {
    if (!identity_ok(expected) || revision(dir, source, identity) != expected ||
        type(last_good_dir) != 'string' || last_good_dir == '' || last_good_dir == '/' ||
        !common.secure_private_dir(last_good_dir)) return false;
    let target_dir = last_good_dir + '/' + expected;
    if (!common.secure_private_dir(target_dir)) return false;
    if (revision(target_dir, source, identity) == expected) return true;
    let content = fs.readfile(dir + '/' + source + '.awg.json');
    if (type(content) != 'string' || revision(dir, source, identity) != expected) return false;
    let t = clock(), tmp = sprintf('%s/.%s-%d-%d.tmp', target_dir, source, t[0], t[1]);
    if (common.write_private_file(tmp, content) == null) { fs.unlink(tmp); return false; }
    if (!fs.rename(tmp, target_dir + '/' + source + '.awg.json')) { fs.unlink(tmp); return false; }
    return revision(target_dir, source, identity) == expected;
}

function save(dir, source, identity, data) {
    if (!source_ok(source) || !identity_ok(identity) || type(dir) != 'string' || dir == '' || dir == '/')
        return false;
    let extracted = require('subscription.amnezia_subscription').extract(data);
    if (extracted.invalid || !length(extracted.configs) || length(extracted.configs) > 32) return false;
    for (let config in extracted.configs) {
        let parsed = parser.parse_conf(config);
        if (!parsed.ok || length(parsed.peers) != 1) return false;
    }
    if (!common.secure_private_dir(dir)) return false;
    let target = dir + '/' + source + '.awg.json';
    let stamp = clock();
    let tmp = sprintf('%s/.%s.%d.%d.tmp', dir, source, stamp[0], stamp[1]);
    let record = { version: 1, identity: identity, configs: extracted.configs };
    let content = sprintf('%J\n', record);
    if (length(content) > 1048576) return false;
    if (common.write_private_file(tmp, content) == null) { fs.unlink(tmp); return false; }
    if (!fs.rename(tmp, target)) { fs.unlink(tmp); return false; }
    return true;
}

return { save, load, load_configs, revision, promote };
