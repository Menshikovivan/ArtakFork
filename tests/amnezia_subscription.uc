let sub = require("subscription.amnezia_subscription");
function expect(ok, text) { if (!ok) die(text + "\n"); }
let config = "[Interface]\nPrivateKey = TESTKEY\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = TESTKEY\nEndpoint = example.invalid:8443\n";
let uri = "vpn://" + replace(replace(replace(b64enc(config), /\+/g, "-"), /\//g, "_"), /=+$/g, "");
let mixed = "vless://example.invalid\n" + uri + "\n" + uri + "\n";
let raw = sub.extract(mixed);
expect(length(raw.configs) == 2 && raw.configs[0] == config && raw.invalid == 0, "raw mixed subscription extraction failed");
let wrapped = sub.extract(b64enc(mixed));
expect(length(wrapped.configs) == 2 && wrapped.configs[1] == config, "base64 subscription extraction failed");
expect(sub.extract("vpn://a").invalid == 1, "invalid base64 accepted");
expect(sub.extract("vpn://" + b64enc("{\"premium\":true}")).invalid == 1, "non-conf vpn key accepted");
expect(length(sub.extract("vless://example.invalid").configs) == 0, "other protocol misidentified");
expect(length(sub.extract("vpn://" + b64enc("[Interface] only")).configs) == 0, "missing peer accepted");
print("3x-ui raw AmneziaWG subscription extraction checks passed\n");
