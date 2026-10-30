#!/usr/bin/env ucode
let changes = require("subscription.change_report");
let parser = require("subscription.parser");
let fs = require("fs");
function expect(ok, message) { if (!ok) die("FAIL: " + message + "\n"); }
function node(name, server, uuid) {
    return { type: "vless", tag: name, server, server_port: 443, uuid };
}
let previous = { outbounds: [
    node("Old name", "one.example", "private-old"),
    node("Changed", "two.example", "private-old"),
    node("Removed", "three.example", "private-old")
] };
let next = { outbounds: [
    node("New name", "one.example", "private-old"),
    node("Changed", "two.example", "private-new"),
    node("Added", "four.example", "private-new")
] };
let report = changes.compare(previous, next);
expect(length(report.added) == 1 && report.added[0] == "Added", "addition");
expect(length(report.removed) == 1 && report.removed[0] == "Removed", "removal");
expect(length(report.changed) == 2, "rename and changed connection");
expect(report.changed[0].kind == "renamed", "rename classification");
expect(report.changed[1].kind == "connection_changed", "parameter change classification");
let text = sprintf("%J", report);
expect(index(text, "private-old") < 0 && index(text, "private-new") < 0 && index(text, ".example") < 0, "no connection secrets or endpoints");
expect(changes.safe_name("vless://private@node.example") == "[name hidden]", "link hidden");
expect(changes.safe_name("token=private") == "[name hidden]", "token hidden");
expect(changes.safe_name("12345678-1234-1234-1234-123456789abc") == "[name hidden]", "uuid hidden");
expect(changes.compare(null, next).baseline == true, "first import baseline");
let duplicate_old = { outbounds: [node("Same", "a.example", "a"), node("Same", "b.example", "b")] };
let duplicate_new = { outbounds: [node("Same", "c.example", "c")] };
let duplicate = changes.compare(duplicate_old, duplicate_new);
expect(length(duplicate.changed) == 0 && length(duplicate.added) == 1 && length(duplicate.removed) == 2, "duplicate names must not guess identity");
let tmp = sprintf("/tmp/forkop-report-test-%d-%d", clock()[0], clock()[1]);
let input = tmp + ".txt", output = tmp + ".json";
fs.writefile(input, "vless://00000000-0000-4000-8000-000000000001@node.test:443#Node\nwireguard://secret\nvless://broken\nnoprotocol\n");
expect(parser.normalize_content_validated(input, output), "normalization succeeds with valid node");
let parsed = json(fs.readfile(output));
expect(parsed.skipped == 3, "skip count");
expect(parsed.skip_reasons.unsupported_protocol == 1, "unsupported protocol reason");
expect(parsed.skip_reasons.invalid_parameters == 1, "invalid parameters reason");
expect(parsed.skip_reasons.missing_protocol == 1, "missing protocol reason");
fs.unlink(input); fs.unlink(output);
print("Subscription change report and secret redaction checks passed\n");
