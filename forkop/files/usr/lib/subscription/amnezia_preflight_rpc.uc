// rpcd executable plugin handler. Input arrives on stdin, never argv.
let fs = require("fs");
let parser = require("subscription.amnezia_conf");
function reply(value) { print(sprintf("%J\n", value)); }
if (ARGV[0] == "list") {
    reply({ preflight: { config: "" }, import_conf: { config: "", section: "" }, import_status: {} });
    exit(0);
}
if (ARGV[0] != "call" || (ARGV[1] != "preflight" && ARGV[1] != "import_conf" && ARGV[1] != "import_status")) exit(1);
let input = fs.open("/dev/stdin", "r");
if (!input) { reply({ ok: false, error: "Request unavailable" }); exit(0); }
let body = input.read(1048577);
input.close();
if (body == null || length(body) > 1048576) { reply({ ok: false, error: "Request too large" }); exit(0); }
let request;
try { request = json(body); } catch (e) { reply({ ok: false, error: "Invalid request" }); exit(0); }
if (type(request) != "object" || (ARGV[1] != "import_status" && (type(request.config) != "string" || length(request.config) > 262144))) {
    reply({ ok: false, error: "Invalid or oversized configuration" }); exit(0);
}
try {
    if (ARGV[1] == "import_conf") {
        let job = require("subscription.amnezia_job");
        if (type(request.section) != 'string' || !match(request.section, /^[A-Za-z0-9_]{1,80}$/)) {
            reply({ ok: false, error: 'Invalid rule section' }); exit(0);
        }
        reply(job.start(request.config, function() {
            let pipe = fs.popen("ucode -L /usr/lib/forkop /usr/lib/forkop/subscription/amnezia_job_worker.uc </dev/null >/dev/null 2>&1 & echo $!", "r");
            if (!pipe) return false;
            let pid = trim(pipe.read("all") || "");
            let result = pipe.close();
            return result == 0 && match(pid, /^[0-9]+$/) != null;
        }, request.section));
        exit(0);
    }
    if (ARGV[1] == "import_status") { reply(require("subscription.amnezia_job").status()); exit(0); }
    let result = parser.parse_conf(request.config);
    if (!result.ok) { reply({ ok: false, error: result.error }); exit(0); }
    reply({ ok: true, peer_count: length(result.peers) });
} catch (e) {
    // Never return exception text: it might contain part of the input.
    reply({ ok: false, error: "Configuration validation failed" });
}
