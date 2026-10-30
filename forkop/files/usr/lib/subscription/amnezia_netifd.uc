// Prepare a new, separately owned OpenWrt AmneziaWG interface. This module
// never commits UCI, starts interfaces, installs packages, or logs key material.
// Callers must use an isolated UCI cursor and perform their own atomic commit,
// netifd reload, connectivity checks, and rollback.
let interface_fields = [
    'private_key', 'addresses', 'mtu', 'listen_port',
    'awg_jc', 'awg_jmin', 'awg_jmax', 'awg_s1', 'awg_s2', 'awg_s3', 'awg_s4',
    'awg_h1', 'awg_h2', 'awg_h3', 'awg_h4', 'awg_i1', 'awg_i2', 'awg_i3',
    'awg_i4', 'awg_i5', 'awg_header_protection_key', 'awg_content_padding_addition',
    'awg_rekey_after_time', 'awg_rekey_timeout', 'awg_reject_after_time',
    'awg_keepalive_timeout', 'awg_max_handshake_attempts',
    'awg_random_trailers', 'awg_disable_cookies'
];
let peer_fields = [ 'public_key', 'preshared_key', 'allowed_ips',
    'endpoint_host', 'endpoint_port', 'persistent_keepalive' ];

function safe_value(value) {
    if (type(value) == 'array') {
        if (!length(value)) return false;
        for (let item in value)
            if (type(item) != 'string' || item == '' || match(item, /[\r\n]/) || index(item, "\x00") >= 0) return false;
        return true;
    }
    return type(value) == 'string' && value != '' && !match(value, /[\r\n]/) && index(value, "\x00") < 0;
}

function copy_fields(source, fields) {
    let out = {};
    for (let key in fields) {
        if (source[key] == null || source[key] == '') continue;
        if (!safe_value(source[key])) return null;
        out[key] = source[key];
    }
    return out;
}

function prepare(parsed, name) {
    // netifd uses the UCI section name as the kernel interface name; Linux
    // limits it to 15 bytes. Restrict to an owned ASCII namespace.
    if (type(name) != 'string' || !match(name, /^afawg_[a-z0-9]{1,8}$/))
        return { ok: false, error: 'Invalid managed interface name' };
    if (type(parsed) != 'object' || parsed.ok !== true || type(parsed.interface) != 'object' ||
        type(parsed.peers) != 'array' || length(parsed.peers) != 1 || type(parsed.peers[0]) != 'object')
        return { ok: false, error: 'Invalid parsed configuration' };
    let iface = copy_fields(parsed.interface, interface_fields);
    let peer = copy_fields(parsed.peers[0], peer_fields);
    if (iface == null || peer == null || !iface.private_key || type(iface.addresses) != 'array' ||
        !peer.public_key || type(peer.allowed_ips) != 'array' || !peer.endpoint_host || !peer.endpoint_port)
        return { ok: false, error: 'Invalid interface or peer fields' };
    // A managed client must initiate its first handshake even when the source
    // does not specify keepalive. Respect explicit zero/off and other values.
    // This is persistent UCI state, so no temporary kernel change survives a
    // killed worker without a corresponding committed configuration.
    if (peer.persistent_keepalive == null) peer.persistent_keepalive = '25';
    // Network policy remains under Forkop control, regardless of imported data.
    iface.proto = 'amneziawg';
    iface.defaultroute = '0';
    iface.peerdns = '0';
    peer.route_allowed_ips = '0';
    return { ok: true, name, peer_name: name + '_peer', peer_type: 'amneziawg_' + name, iface, peer };
}

// Only stages two new sections. It does not overwrite or delete existing user
// sections, including a managed section from a previous operation. Updates need
// a separate transactional swap coordinated with active connections.
function stage_new(cursor, parsed, name) {
    let plan = prepare(parsed, name);
    if ((type(cursor) != 'object' && type(cursor) != 'resource') || plan.ok !== true)
        return { ok: false, error: 'Invalid stage request' };
    let created_interface = false, created_peer = false;
    try {
        if (cursor.load('network') == null)
            return { ok: false, error: 'Cannot load network configuration' };
        if (cursor.get('network', plan.name) != null || cursor.get('network', plan.peer_name) != null)
            return { ok: false, error: 'Interface name already exists' };
        created_interface = true;
        if (cursor.set('network', plan.name, 'interface') == null) die('set failed');
        for (let key in keys(plan.iface))
            if (cursor.set('network', plan.name, key, plan.iface[key]) == null) die('set failed');
        created_peer = true;
        if (cursor.set('network', plan.peer_name, plan.peer_type) == null) die('set failed');
        for (let key in keys(plan.peer))
            if (cursor.set('network', plan.peer_name, key, plan.peer[key]) == null) die('set failed');
        return { ok: true, name: plan.name };
    }
    catch (e) {
        try { if (created_peer) cursor.delete('network', plan.peer_name); } catch (ignored) {}
        try { if (created_interface) cursor.delete('network', plan.name); } catch (ignored) {}
        return { ok: false, error: 'Could not stage interface' };
    }
}

return { prepare, stage_new };
