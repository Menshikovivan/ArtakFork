// Extract 3x-ui raw vpn:// profiles. The caller must validate each returned
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

return { extract };
