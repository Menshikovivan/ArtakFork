let probe = require("diagnostics.service_check");
function expect(value, message) { if (!value) die(message + "\n"); }
let config = { outbounds: [
    { tag: "selector", type: "selector", outbounds: ["auto", "direct"] },
    { tag: "auto", type: "urltest", outbounds: ["leaf"] },
    { tag: "leaf", type: "vless" },
    { tag: "direct", type: "direct" }
] };
let proxies = {
    selector: { now: "auto" }, auto: { now: "leaf" },
    leaf: { type: "VLESS" }, direct: { type: "Direct" }
};
expect(probe.selected_leaf(proxies, config, "selector") == "leaf", "nested active group must resolve to leaf");
expect(probe.selected_leaf(proxies, config, "leaf") == "leaf", "explicit node must resolve");
expect(probe.selected_leaf(proxies, config, "direct") == null, "direct outbound must be rejected");
proxies.selector.now = "direct";
expect(probe.selected_leaf(proxies, config, "selector") == null, "group selecting direct must be rejected");
proxies.selector.now = "leaf";
expect(probe.selected_leaf(proxies, config, "selector") == null, "unlisted group member must be rejected");
proxies.selector.now = "auto";
proxies.auto.now = "selector";
expect(probe.selected_leaf(proxies, config, "selector") == null, "invalid/cyclic group must be rejected");
expect(probe.selected_leaf(proxies, config, "missing") == null, "missing node must be rejected");
print("Service check: active group resolution and direct protection passed\n");
