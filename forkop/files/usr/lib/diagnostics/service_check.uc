// Resolve the currently selected leaf without modifying URLTest state.
function selected_leaf(proxies, config, requested) {
    if (type(proxies) != "object" || type(config) != "object" || type(requested) != "string" || requested == "")
        return null;
    let by_tag = {};
    for (let outbound in config.outbounds || [])
        if (type(outbound) == "object" && type(outbound.tag) == "string")
            by_tag[outbound.tag] = outbound;
    let seen = {};
    let tag = requested;
    for (let i = 0; i < 32; i++) {
        if (seen[tag] || type(proxies[tag]) != "object" || type(by_tag[tag]) != "object")
            return null;
        seen[tag] = true;
        let outbound = by_tag[tag];
        let t = lc("" + (outbound.type || ""));
        if (t == "selector" || t == "urltest" || t == "priority") {
            let next = proxies[tag].now;
            if (type(next) != "string" || next == "" || !contains(outbound.outbounds || [], next))
                return null;
            tag = next;
            continue;
        }
        if (t == "" || t == "direct" || t == "block" || t == "dns")
            return null;
        return tag;
    }
    return null;
}

return { selected_leaf };
