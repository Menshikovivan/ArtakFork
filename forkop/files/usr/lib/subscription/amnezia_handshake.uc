// Read handshake timestamps without logging or returning peer keys or output.
// A recent handshake proves peer liveness, not usable service routing.
let activation = require('subscription.amnezia_activate');
function verify(name, peer, timeout_ms, runner, pause, now, wall) {
    if (type(name) != 'string' || !match(name, /^afawg_[a-z0-9]{1,8}$/) ||
        type(peer) != 'string' || !match(peer, /^[A-Za-z0-9+\/]{43}=$/) ||
        type(timeout_ms) != 'int' || timeout_ms < 1000 || timeout_ms > 30000)
        return { ok: false, error: 'Invalid handshake request' };
    runner = runner || activation.run;
    pause = pause || sleep;
    now = now || function() { let t = clock(true); return t == null ? null : t[0] * 1000 + int(t[1] / 1000000); };
    wall = wall || time;
    let start = now();
    if (start == null) return { ok: false, error: 'Monotonic clock unavailable' };
    let end = start + timeout_ms;
    while (now() < end) {
        // timeout is supplied by BusyBox/coreutils; stdout contains peer keys
        // and remains in process memory, never logged or returned to caller.
        let r = runner(['timeout', '3', 'awg', 'show', name, 'latest-handshakes']);
        if (!r.ok) return { ok: false, error: 'Cannot inspect AWG handshake' };
        let epoch = wall();
        for (let line in split(r.output || '', '\n')) {
            let fields = split(trim(line), /[ \t]+/);
            if (length(fields) == 2 && fields[0] == peer && match(fields[1], /^[0-9]+$/)) {
                let seen = int(fields[1]);
                if (seen > 0 && epoch >= seen && epoch - seen <= 180) return { ok: true };
            }
        }
        if (now() < end) pause(500);
    }
    return { ok: false, error: 'Recent AWG handshake not observed' };
}
return { verify };
