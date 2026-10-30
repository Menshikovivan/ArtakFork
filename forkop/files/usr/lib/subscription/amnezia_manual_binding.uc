// Assign an opaque, persistent manual-source ID to a single committed Forkop
// connection section. Caller holds lifecycle locks and uses an isolated UCI
// cursor; other UCI sessions are not coordinated by these locks.
let manual = require('subscription.amnezia_manual_source');
function fingerprint(section) {
    if (type(section) != 'object') return null;
    let out = {};
    for (let key in sort(keys(section)))
        if (key != 'manual_awg_id' && (substr(key, 0, 1) != '.' || key == '.type')) out[key] = section[key];
    return sprintf('%J', out);
}
function bind(cursor, section, fresh_id) {
    if (type(section) != 'string' || !match(section, /^[A-Za-z0-9_]{1,80}$/) ||
        (type(cursor) != 'object' && type(cursor) != 'resource')) return {ok:false,error:'Invalid rule'};
    try {
        if (cursor.load('forkop') == null) return {ok:false,error:'Cannot read rules'};
        let current = cursor.get_all('forkop', section);
        if (type(current) != 'object' || current.action != 'connection') return {ok:false,error:'Rule is not a connection'};
        let id = current.manual_awg_id;
        if (id == null || id == '') {
            id = fresh_id();
            if (manual.from_id(id) == null || cursor.set('forkop', section, 'manual_awg_id', id) == null || !cursor.commit('forkop'))
                return {ok:false,error:'Cannot save manual source identity'};
            current = cursor.get_all('forkop', section);
        }
        let identity = manual.from_id(id), stamp = fingerprint(current);
        if (identity == null || stamp == null || current.manual_awg_id != id)
            return {ok:false,error:'Invalid manual source identity'};
        return {ok:true, source:identity.source, identity:identity.identity, id, fingerprint:stamp};
    } catch (e) { return {ok:false,error:'Cannot bind manual source'}; }
}
function current(cursor, section, binding) {
    try {
        if (cursor.load('forkop') == null) return false;
        let value = cursor.get_all('forkop', section);
        return type(value) == 'object' && value.action == 'connection' &&
            value.manual_awg_id == binding.id && fingerprint(value) == binding.fingerprint;
    } catch (e) { return false; }
}
return { bind, current };
