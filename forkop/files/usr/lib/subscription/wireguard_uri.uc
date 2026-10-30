// Strict 3x-ui-compatible plain WireGuard share links. Returned configs contain
// secrets: callers must treat them like .conf files and never log them.
let parser = require('subscription.amnezia_conf');

function decode(value, form) {
    let out = '';
    for (let i = 0; i < length(value); i++) {
        let c = substr(value, i, 1);
        if (c == '%') {
            let h = substr(value, i + 1, 2);
            if (length(h) != 2 || !match(h, /^[0-9a-fA-F]{2}$/)) return null;
            c = chr(hex(h));
            i += 2;
        } else if (form && c == '+') c = ' ';
        let n = ord(c);
        if (n < 32 || n == 127) return null;
        out += c;
    }
    return out;
}

function parse(link) {
    if (type(link) != 'string' || length(link) > 8192) return { ok: false };
    // ucode's POSIX regexp engine does not accept JavaScript hex escapes.
    for (let i = 0; i < length(link); i++) {
        let c = ord(substr(link, i, 1));
        if (c <= 32 || c == 127) return { ok: false };
    }
    let prefix = substr(link, 0, 12) == 'wireguard://' ? 12 : substr(link, 0, 5) == 'wg://' ? 5 : 0;
    if (!prefix) return { ok: false };
    let body = substr(link, prefix), fragment = index(body, '#');
    if (fragment >= 0) body = substr(body, 0, fragment);
    let question = index(body, '?');
    if (question < 0) return { ok: false };
    let authority = substr(body, 0, question), query = substr(body, question + 1);
    let at = index(authority, '@');
    if (at <= 0 || at != rindex(authority, '@')) return { ok: false };
    let secret = decode(substr(authority, 0, at), false);
    let endpoint = substr(authority, at + 1);
    if (secret == null || endpoint == '' || index(endpoint, '%') >= 0 || index(endpoint, '/') >= 0)
        return { ok: false };
    let aliases = {
        publickey: 'publickey', public_key: 'publickey', peerpublickey: 'publickey',
        address: 'address', ip: 'address', mtu: 'mtu', dns: 'dns',
        presharedkey: 'presharedkey', preshared_key: 'presharedkey', 'pre-shared-key': 'presharedkey', psk: 'presharedkey',
        keepalive: 'keepalive', persistentkeepalive: 'keepalive', persistent_keepalive: 'keepalive',
        allowedips: 'allowedips', allowed_ips: 'allowedips'
    };
    let values = {};
    for (let item in split(query, '&')) {
        let eq = index(item, '=');
        if (eq <= 0) return { ok: false };
        let rawname = decode(substr(item, 0, eq), true), value = decode(substr(item, eq + 1), true);
        if (rawname == null || value == null || value == '') return { ok: false };
        let name = aliases[lc(rawname)];
        if (name == null || values[name] != null) return { ok: false };
        values[name] = value;
    }
    if (!values.publickey || !values.address) return { ok: false };
    let config = '[Interface]\nPrivateKey = ' + secret + '\nAddress = ' + values.address + '\n';
    if (values.mtu) config += 'MTU = ' + values.mtu + '\n';
    if (values.dns) config += 'DNS = ' + values.dns + '\n';
    config += '[Peer]\nPublicKey = ' + values.publickey + '\n';
    if (values.presharedkey) config += 'PresharedKey = ' + values.presharedkey + '\n';
    config += 'AllowedIPs = ' + (values.allowedips || '0.0.0.0/0,::/0') + '\nEndpoint = ' + endpoint + '\n';
    if (values.keepalive) config += 'PersistentKeepalive = ' + values.keepalive + '\n';
    let parsed = parser.parse_conf(config);
    if (!parsed.ok || length(parsed.peers) != 1) return { ok: false };
    return { ok: true, config };
}

return { parse };
