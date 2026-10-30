// Explicit netifd activation of a previously committed interface. No config
// values or secrets are passed on the command line. network reload is global:
// callers must coordinate pending UCI changes and treat failures as uncertain.
let fs = require('fs');
function quote(s) { return "'" + replace('' + s, /'/g, "'\\''") + "'"; }
function run(argv) {
    let args = [];
    for (let value in argv) push(args, quote(value));
    let pipe = fs.popen(join(' ', args) + ' 2>/dev/null', 'r');
    if (!pipe) return { ok: false, output: '' };
    let output = pipe.read('all');
    let status = pipe.close();
    return { ok: status != null && int(status) == 0, output: output == null ? '' : output };
}
function valid_name(name) {
    return type(name) == 'string' && match(name, /^afawg_[a-z0-9]{1,8}$/) != null;
}
function contains_address(status, cidr) {
    let parts = split(cidr, '/');
    if (length(parts) != 2) return false;
    let family = index(parts[0], ':') >= 0 ? 'ipv6-address' : 'ipv4-address';
    if (type(status[family]) != 'array') return false;
    for (let item in status[family])
        if (item.address == parts[0] && int(item.mask) == int(parts[1])) return true;
    return false;
}
function ready(status, name, addresses) {
    if (type(status) != 'object' || status.up != true || status.l3_device != name || type(addresses) != 'array' || !length(addresses)) return false;
    for (let addr in addresses) if (!contains_address(status, addr)) return false;
    return true;
}
function start(name, addresses, timeout_ms, runner, pause, now) {
    if (!valid_name(name) || type(addresses) != 'array' || !length(addresses) ||
        type(timeout_ms) != 'int' || timeout_ms < 1000 || timeout_ms > 30000)
        return { ok: false, error: 'Invalid interface activation request' };
    for (let addr in addresses)
        if (type(addr) != 'string' || !match(addr, /^[0-9a-fA-F:.]+\/[0-9]{1,3}$/))
            return { ok: false, error: 'Invalid interface address' };
    runner = runner || run;
    pause = pause || sleep;
    now = now || function() { let t = clock(true); return t == null ? null : t[0] * 1000 + int(t[1] / 1000000); };
    let initial = now();
    if (initial == null) return { ok: false, error: 'Monotonic clock unavailable' };
    let end = initial + timeout_ms;
    let object = 'network.interface.' + name;
    // Each ubus request has its own 3-second bound. The overall deadline can
    // exceed timeout_ms by at most one in-flight request.
    if (!runner(['ubus', '-t', '3', 'call', 'network', 'reload', '{}']).ok)
        return { ok: false, error: 'Network reload failed; state is uncertain' };
    if (now() >= end || !runner(['ubus', '-t', '3', 'call', object, 'up', '{}']).ok)
        return { ok: false, error: 'Interface start failed or timed out; state is uncertain' };
    while (now() < end) {
        let reply = runner(['ubus', '-t', '3', 'call', object, 'status', '{}']);
        let status = null;
        if (reply.ok) try { status = json(reply.output); } catch (ignored) {}
        if (ready(status, name, addresses)) return { ok: true, name };
        if (now() < end) pause(250);
    }
    return { ok: false, error: 'Interface readiness timed out; state is uncertain' };
}
function stop(name, runner) {
    if (!valid_name(name)) return { ok: false, error: 'Invalid interface name' };
    runner = runner || run;
    return runner(['ubus', '-t', '3', 'call', 'network.interface.' + name, 'down', '{}']).ok ?
        { ok: true } : { ok: false, error: 'Interface stop failed; state is uncertain' };
}
function reload(runner) {
    runner = runner || run;
    return runner(['ubus', '-t', '3', 'call', 'network', 'reload', '{}']).ok ?
        { ok: true } : { ok: false, error: 'Network reload failed; state is uncertain' };
}
return { start, stop, reload, run, ready };
