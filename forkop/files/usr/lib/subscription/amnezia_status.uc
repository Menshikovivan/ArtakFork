// Persistent metadata for an AWG-only source. Contains subscription URL and
// request-profile values: use only in memory and a private root-owned folder.
// A status is never proof of readiness; restore the manifest and verify the
// current UCI, network rules, handshake and firewall guard before use.
let fs = require('fs');
let common = require('core.common');
let identity_module = require('subscription.amnezia_identity');
let active = require('subscription.amnezia_active');
let store = require('subscription.amnezia_store');
function valid_source(s) { return type(s) == 'string' && match(s, /^[A-Za-z0-9_-]{1,100}$/); }
function read(dir, source) {
    if (type(dir) != 'string' || dir == '' || dir == '/' || !valid_source(source)) return null;
    let content = fs.readfile(dir + '/' + source + '.json');
    if (type(content) != 'string' || length(content) > 16384) return null;
    let r; try { r = json(content); } catch (e) { return null; }
    if (type(r) != 'object' || r.version != 1 || r.source != source ||
        type(r.url) != 'string' || r.url == '' || type(r.user_agent) != 'string' || type(r.hwid) != 'string' ||
        type(r.identity) != 'string' || !match(r.identity, /^[0-9a-f]{64}$/) ||
        type(r.revision) != 'string' || !match(r.revision, /^[0-9a-f]{64}$/) ||
        (r.mode != null && r.mode != 'only' && r.mode != 'mixed') ||
        (r.mode == 'mixed' && (type(r.legacy_revision) != 'string' || !match(r.legacy_revision, /^[0-9a-f]{64}$/)))) return null;
    if (r.mode == null) r.mode = 'only';
    return r;
}
function save(dir, active_dir, good_dir, source, url, user_agent, hwid, identity, revision, mode, legacy_revision) {
    mode = mode || 'only';
    if (type(dir) != 'string' || dir == '' || dir == '/' || !valid_source(source) ||
        type(url) != 'string' || url == '' || type(user_agent) != 'string' || type(hwid) != 'string' ||
        (mode != 'only' && mode != 'mixed') || (mode == 'mixed' && (type(legacy_revision) != 'string' || !match(legacy_revision, /^[0-9a-f]{64}$/))) ||
        type(revision) != 'string' || !match(revision, /^[0-9a-f]{64}$/) ||
        !common.secure_private_dir(dir)) return false;
    if (identity_module.calculate(dir, source, url, user_agent, hwid) != identity ||
        active.peek(active_dir, source, identity) != revision ||
        store.revision(good_dir + '/' + revision, source, identity) != revision) return false;
    let record = { version: 1, source, url, user_agent, hwid, identity, revision, mode };
    if (mode == 'mixed') record.legacy_revision = legacy_revision;
    if (length(sprintf('%J\n', record)) > 16384) return false;
    let t = clock(), tmp = sprintf('%s/.%s-%d-%d.tmp', dir, source, t[0], t[1]);
    if (common.write_private_json_file(tmp, record) == null) { fs.unlink(tmp); return false; }
    if (!fs.rename(tmp, dir + '/' + source + '.json')) { fs.unlink(tmp); return false; }
    return true;
}
return { save, read };
