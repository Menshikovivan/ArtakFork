// Extract 3x-ui vpn:// and plain WireGuard share links. The caller must validate each returned
// configuration before use; this module never writes or logs credentials.
function decode64(value) {
    if (type(value) != "string" || value == "" || length(value) > 1398104 ||
        !match(value, /^[A-Za-z0-9+\/_-]+={0,2}$/))
        return null;
    value = replace(replace(value, /-/g, "+"), /_/g, "/");
    let rem = length(value) % 4;
    if (rem == 1) return null;
    if (rem > 1) {
        if (index(value, "=") >= 0) return null;
        for (let i = rem; i < 4; i++) value += "=";
    }
    try { return b64dec(value); }
    catch (e) { return null; }
}

function extract(data) {
    let result = { configs: [], invalid: 0 };
    if (type(data) != "string" || length(data) > 1048576) return result;
    // 3x-ui may wrap a list of links in base64, or send it directly.
    if (index(data, "://") < 0) {
        let decoded = decode64(replace(data, /[\r\n\t ]/g, ""));
        if (decoded == null || length(decoded) > 1048576) return result;
        data = decoded;
    }
    for (let line in split(replace(data, /\r/g, ""), "\n")) {
        line = replace(line, /^[ \t]+|[ \t]+$/g, "");
        if (substr(line, 0, 12) == 'wireguard://' || substr(line, 0, 5) == 'wg://') {
            let wg = require('subscription.wireguard_uri').parse(line);
            if (!wg.ok) result.invalid++;
            else push(result.configs, wg.config);
            continue;
        }
        if (substr(line, 0, 6) != "vpn://") continue;
        let config = decode64(substr(line, 6));
        if (config == null || length(config) > 65536 ||
            index(config, "[Interface]") < 0 || index(config, "[Peer]") < 0) {
            result.invalid++;
            continue;
        }
        push(result.configs, config);
    }
    return result;
}

// Reject the whole AWG update if any vpn:// item is malformed or unsupported.
// This prevents a partially valid feed from replacing last-known-good profiles.
function validated(data) {
    let source = extract(data), profiles = [];
    if (source.invalid || !length(source.configs))
        return { ok: false, error: 'No complete AmneziaWG profiles' };
    let parser = require('subscription.amnezia_conf');
    for (let item in source.configs) {
        let parsed = parser.parse_conf(item);
        if (!parsed.ok || length(parsed.peers) != 1)
            return { ok: false, error: 'Invalid or unsupported AmneziaWG profile' };
        push(profiles, parsed);
    }
    return { ok: true, profiles };
}

function only_awg(data) {
    if (type(data) != 'string' || length(data) > 1048576) return false;
    if (index(data, '://') < 0) data = decode64(replace(data, /[\r\n\t ]/g, ''));
    if (type(data) != 'string') return false;
    let seen = false;
    for (let line in split(replace(data, /\r/g, ''), '\n')) {
        line = trim(line);
        if (line == '') continue;
        if (substr(line, 0, 6) != 'vpn://' && substr(line, 0, 12) != 'wireguard://' && substr(line, 0, 5) != 'wg://') return false;
        seen = true;
    }
    return seen && validated(data).ok;
}

return { extract, validated, only_awg };
