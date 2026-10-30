// Explicit opt-in shared by rpcd and lifecycle. Read committed configuration
// with a separate cursor; reject shared pending deltas, any error means disabled.
function enabled(cursor) {
    try {
        if (cursor == null) {
            // libuci always adds /tmp/.uci to the delta path even with an
            // alternate savedir. Never interpret a staged toggle as committed.
            if (require('subscription.amnezia_pending').pending('/tmp/.uci/forkop')) return false;
            cursor = require('uci').cursor('/etc/config', '/dev/null', '');
        }
        if (!cursor || cursor.load('forkop') == null) return false;
        return cursor.get('forkop', 'settings', 'awg_experimental') == '1';
    } catch (e) { return false; }
}
return { enabled };
