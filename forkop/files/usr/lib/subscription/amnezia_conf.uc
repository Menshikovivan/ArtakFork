// Pure .conf parser. The returned object contains secrets and must never be
// logged or sent to a remote service. No configuration is changed here.
let ip = require("core.ip");

const interface_keys = {
    privatekey: "private_key", address: "addresses", dns: "dns", mtu: "mtu", listenport: "listen_port",
    jc: "awg_jc", jmin: "awg_jmin", jmax: "awg_jmax",
    s1: "awg_s1", s2: "awg_s2", s3: "awg_s3", s4: "awg_s4",
    h1: "awg_h1", h2: "awg_h2", h3: "awg_h3", h4: "awg_h4",
    i1: "awg_i1", i2: "awg_i2", i3: "awg_i3", i4: "awg_i4", i5: "awg_i5",
    headerprotectionkey: "awg_header_protection_key", contentpaddingaddition: "awg_content_padding_addition",
    rekeyaftertime: "awg_rekey_after_time", rekeytimeout: "awg_rekey_timeout",
    rejectaftertime: "awg_reject_after_time", keepalivetimeout: "awg_keepalive_timeout",
    maxhandshakeattempts: "awg_max_handshake_attempts", randomtrailers: "awg_random_trailers",
    disablecookies: "awg_disable_cookies"
};
const peer_keys = { publickey: "public_key", presharedkey: "preshared_key", allowedips: "allowed_ips", endpoint: "endpoint", persistentkeepalive: "persistent_keepalive" };

function failure(message) { return { ok: false, error: message }; }
function key_valid(v) { return type(v) == "string" && match(v, /^[A-Za-z0-9+\/]{43}=$/) != null; }
function numbers(v, max, allow_range) {
    if (type(v) != "string" || match(v, allow_range ? /^[0-9]+(-[0-9]+)?$/ : /^[0-9]+$/) == null) return false;
    let parts = split(v, "-");
    if (length(parts[0]) > 10 || (length(parts) > 1 && length(parts[1]) > 10)) return false;
    let a = int(parts[0]), b = length(parts) > 1 ? int(parts[1]) : a;
    return a >= 0 && a <= b && b <= max;
}
function list_ip(v) {
    let result = [];
    for (let item in split(replace(v, /[ \t]+/g, ""), ",")) {
        if (!ip.valid_ip_or_cidr(item)) return null;
        push(result, item);
    }
    return length(result) ? result : null;
}

function parse_conf(text) {
    if (type(text) != "string" || length(text) > 262144 || index(text, "\x00") >= 0)
        return failure("Invalid configuration input");
    let iface = {}, peers = [], current = null, section = "", have_interface = false;
    for (let raw in split(text, "\n")) {
        let line = trim(replace(raw, /\r$/, ""));
        if (line == "" || substr(line, 0, 1) == "#" || substr(line, 0, 1) == ";") continue;
        line = trim(replace(line, /[ \t]+[#;].*$/, ""));
        if (length(line) > 16384) return failure("Configuration line too long");
        if (match(line, /^\[Interface\]$/i)) {
            if (have_interface || length(peers)) return failure("Duplicate or misplaced interface section");
            have_interface = true; current = iface; section = "interface"; continue;
        }
        if (match(line, /^\[Peer\]$/i)) {
            if (!have_interface || length(peers) >= 32) return failure("Invalid peer section");
            current = {}; push(peers, current); section = "peer"; continue;
        }
        let equal = index(line, "=");
        if (current == null || equal <= 0) return failure("Invalid configuration line");
        let name = lc(trim(substr(line, 0, equal))), value = trim(substr(line, equal + 1));
        let field = section == "interface" ? interface_keys[name] : peer_keys[name];
        if (field == null) return failure("Unsupported configuration field");
        if (value == "" || current[field] != null || match(value, /[\x00-\x1f\x7f]/)) return failure("Empty or duplicate configuration field");
        current[field] = value;
    }
    if (!have_interface || !key_valid(iface.private_key) || iface.addresses == null || length(peers) == 0)
        return failure("PrivateKey, Address and at least one peer are required");
    if (iface.awg_header_protection_key != null && !key_valid(iface.awg_header_protection_key)) return failure("Invalid header protection key");
    if (iface.addresses != null) { iface.addresses = list_ip(iface.addresses); if (iface.addresses == null) return failure("Invalid interface address"); }
    if (iface.dns != null) {
        iface.dns = list_ip(iface.dns);
        if (iface.dns == null) return failure("Invalid DNS address");
        for (let item in iface.dns) if (!ip.valid_ip(item)) return failure("Invalid DNS address");
    }
    for (let name in ["mtu", "listen_port", "awg_jc", "awg_jmin", "awg_jmax", "awg_s1", "awg_s2", "awg_s3", "awg_s4"])
        if (iface[name] != null && !numbers(iface[name], 65535, false)) return failure("Invalid numeric interface parameter");
    if (iface.mtu != null && (int(iface.mtu) < 576 || int(iface.mtu) > 9000)) return failure("Invalid MTU");
    if (iface.awg_jmin != null && iface.awg_jmax != null && int(iface.awg_jmin) > int(iface.awg_jmax)) return failure("Invalid junk packet range");
    for (let name in ["awg_h1", "awg_h2", "awg_h3", "awg_h4"])
        if (iface[name] != null && !numbers(iface[name], 4294967295, true)) return failure("Invalid header range");
    let ranges = [];
    for (let i = 1; i <= 4; i++) {
        let value = iface["awg_h" + i] || "" + i, parts = split(value, "-");
        let lo = int(parts[0]), hi = length(parts) > 1 ? int(parts[1]) : lo;
        for (let r in ranges) if (lo <= r[1] && r[0] <= hi) return failure("Overlapping header ranges");
        push(ranges, [lo, hi]);
    }
    for (let name in ["awg_content_padding_addition", "awg_rekey_after_time", "awg_rekey_timeout", "awg_reject_after_time", "awg_keepalive_timeout", "awg_max_handshake_attempts"])
        if (iface[name] != null && !numbers(iface[name], 65535, true)) return failure("Invalid timing or padding range");
    for (let name in ["awg_random_trailers", "awg_disable_cookies"]) {
        if (iface[name] == null) continue;
        let value = lc(iface[name]);
        if (value != "on" && value != "off" && value != "1" && value != "0") return failure("Invalid boolean parameter");
        iface[name] = value == "on" || value == "1" ? "1" : "0";
    }
    if (iface.awg_header_protection_key != null)
        for (let name in ["awg_s1", "awg_s2", "awg_s3", "awg_s4"])
            if (iface[name] == null || int(iface[name]) < 12) return failure("Header protection requires S1-S4 of at least 12");
    for (let peer in peers) {
        if (!key_valid(peer.public_key) || (peer.preshared_key != null && !key_valid(peer.preshared_key))) return failure("Invalid peer key");
        peer.allowed_ips = peer.allowed_ips == null ? ["0.0.0.0/0", "::/0"] : list_ip(peer.allowed_ips);
        if (peer.allowed_ips == null) return failure("Invalid allowed IPs");
        if (peer.persistent_keepalive == "off") delete peer.persistent_keepalive;
        if (peer.persistent_keepalive != null && !numbers(peer.persistent_keepalive, 65535, true)) return failure("Invalid keepalive");
        if (peer.endpoint == null) return failure("Peer endpoint is required");
        let endpoint = match(peer.endpoint, /^\[([0-9A-Fa-f:.]+)\]:([0-9]+)$/) || match(peer.endpoint, /^([A-Za-z0-9._-]+):([0-9]+)$/);
        if (!endpoint || !numbers(endpoint[2], 65535, false) || int(endpoint[2]) == 0 || (index(endpoint[1], ":") >= 0 && !ip.valid_ipv6(endpoint[1]))) return failure("Invalid peer endpoint");
        peer.endpoint_host = endpoint[1]; peer.endpoint_port = endpoint[2]; delete peer.endpoint;
        peer.route_allowed_ips = "0";
    }
    iface.proto = "amneziawg";
    return { ok: true, interface: iface, peers };
}

return { parse_conf };
