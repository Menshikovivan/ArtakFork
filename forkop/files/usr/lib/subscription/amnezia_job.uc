// One private job at a time. Secrets are never returned by status or passed in argv.
let fs = require('fs');
let common = require('core.common');
let parser = require('subscription.amnezia_conf');
let root = getenv('ARTAK_AWG_JOB_TEST_DIR') || '/tmp/artak-awg-job';
// Only fixed internal codes may cross the RPC boundary; never expose errors or input.
function safe_diagnostic(code) {
    return index(['interface_not_ready', 'handshake_timeout', 'handshake_check_failed', 'activation_failed', 'publication_failed'], code) >= 0 ? code : 'unknown';
}
function private_root(create) {
    let self = fs.stat('/proc/self');
    if (self == null) return false;
    let current = fs.lstat(root);
    if (current == null && create) {
        if (!fs.mkdir(root, 0700)) return false;
        current = fs.lstat(root);
    }
    // Never follow a pre-created symlink or chmod a directory controlled by
    // another local user. The private directory owns all later paths.
    return current != null && current.type == 'directory' && current.uid == self.uid &&
        (current.mode & 63) == 0;
}
function write_state(state) {
    let tmp = root + '/state.tmp';
    return common.write_private_json_file(tmp, state) != null && fs.rename(tmp, root + '/state.json');
}
function status() {
    if (!private_root(false)) return { ok: false, state: 'unknown' };
    let raw = fs.readfile(root + '/state.json'), state = null;
    if (raw == null || length(raw) > 4096) return { ok: false, state: 'unknown' };
    try { state = json(raw); } catch (e) { return { ok: false, state: 'unknown' }; }
    if (type(state) != 'object') return { ok: false, state: 'unknown' };
    if (state.state == 'running') {
        // A killed worker may leave the input behind. Keep the lock and never
        // start a second job until the router state has been inspected.
        if (type(state.started) == 'int' && time() - state.started > 180) {
            fs.unlink(root + '/input');
            return { ok: true, state: 'stale' };
        }
        return { ok: true, state: 'running' };
    }
    if (state.state == 'done' && type(state.name) == 'string' && match(state.name, /^afawg_[a-z0-9]{1,8}$/))
        return { ok: true, state: 'done', name: state.name };
    if (state.state == 'failed') return { ok: true, state: 'failed', diagnostic: safe_diagnostic(state.diagnostic), cleanup_required: state.cleanup_required === true };
    return { ok: false, state: 'unknown' };
}
function start(config, launcher, section) {
    if (type(config) != 'string' || length(config) > 65536 || !parser.parse_conf(config).ok)
        return { ok: false, error: 'Invalid configuration' };
    if (section != null && (type(section) != 'string' || !match(section, /^[A-Za-z0-9_]{1,80}$/)))
        return { ok: false, error: 'Invalid rule section' };
    if (!private_root(true)) return { ok: false, error: 'Unable to prepare job' };
    // Atomic mkdir prevents parallel start requests, including finished-job cleanup races.
    if (!fs.mkdir(root + '/lock', 0700)) return { ok: false, error: 'Job is active or requires inspection' };
    if (common.write_private_json_file(root + '/input', { config, section }) == null || !write_state({ state: 'running', started: time() })) {
        fs.unlink(root + '/input'); fs.rmdir(root + '/lock'); return { ok: false, error: 'Unable to prepare job' };
    }
    let ok = false;
    try { ok = launcher(); } catch (e) {}
    if (!ok) {
        fs.unlink(root + '/input'); write_state({ state: 'failed' }); fs.rmdir(root + '/lock');
        return { ok: false, error: 'Unable to launch job' };
    }
    return { ok: true, state: 'running' };
}
function run(driver) {
    if (!private_root(false)) return;
    let raw = fs.readfile(root + '/input'), request = null;
    fs.unlink(root + '/input');
    try { if (raw != null) request = json(raw); } catch (e) {}
    let result = null;
    try { if (type(request) == 'object' && type(request.config) == 'string') result = driver(request.config, request.section); } catch (e) {}
    let state = type(result) == 'object' && result.ok === true &&
        type(result.name) == 'string' && match(result.name, /^afawg_[a-z0-9]{1,8}$/) ?
        { state: 'done', name: result.name } : { state: 'failed', diagnostic: safe_diagnostic(result?.diagnostic), cleanup_required: result?.cleanup_required === true };
    if (write_state(state)) fs.rmdir(root + '/lock');
    // A failed state write retains the lock; never silently allow another apply.
}
return { start, status, run };
