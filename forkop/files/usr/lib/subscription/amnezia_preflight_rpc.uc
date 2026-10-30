// rpcd executable plugin handler. Input arrives on stdin, never argv.
let fs = require("fs");
let parser = require("subscription.amnezia_conf");
function reply(value) { print(sprintf("%J\n", value)); }
if (ARGV[0] == "list") {
    reply({ preflight: { config: "" }, import_conf: { config: "" } });
    exit(0);
}
if (ARGV[0] != "call" || (ARGV[1] != "preflight" && ARGV[1] != "import_conf")) exit(1);
let input = fs.open("/dev/stdin", "r");
if (!input) { reply({ ok: false, error: "Request unavailable" }); exit(0); }
let body = input.read(1048577);
input.close();
if (body == null || length(body) > 1048576) { reply({ ok: false, error: "Request too large" }); exit(0); }
let request;
try { request = json(body); } catch (e) { reply({ ok: false, error: "Invalid request" }); exit(0); }
if (type(request) != "object" || type(request.config) != "string" || length(request.config) > 262144) {
    reply({ ok: false, error: "Invalid or oversized configuration" }); exit(0);
}
try {
    if (ARGV[1] == "import_conf") {
        let importer = require("subscription.amnezia_rpc_import");
        let uci = require("uci");
        let checker = require("subscription.amnezia_runtime_check");
        let backend = require("subscription.amnezia_apply");
        reply(importer.apply(request.config, { cursor: function() { return uci.cursor(); }, check: checker.check, apply: backend.apply }));
        exit(0);
    }
    let result = parser.parse_conf(request.config);
    if (!result.ok) { reply({ ok: false, error: result.error }); exit(0); }
    reply({ ok: true, peer_count: length(result.peers) });
} catch (e) {
    // Never return exception text: it might contain part of the input.
    reply({ ok: false, error: "Configuration validation failed" });
}
