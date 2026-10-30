#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT_DIR/forkop/files/usr/lib"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# The main entry may disappear from a refreshed subscription. The explicitly
# configured second level must remain usable, and no direct outbound may appear.
cat >"$WORK_DIR/config.json" <<'JSON'
{
 "settings": {".name":"settings", ".type":"settings"},
 "section": [{".name":"chat", ".type":"section", "enabled":"1", "action":"connection",
   "selector_proxy_links":["vless://00000000-0000-4000-8000-000000000001@backup.example:443?encryption=none&security=tls&sni=backup.example&type=ws#DE%20backup"]}],
 "priority_group": [{".name":"group", ".type":"priority_group", "section":"chat", "name":"Germany"}],
 "priority_level": [
  {".name":"primary", ".type":"priority_level", "group":"group", "name":"Primary", "order":"0", "filter_mode":"include", "include_regex":["^DE main$"]},
  {".name":"reserve", ".type":"priority_level", "group":"group", "name":"Backup", "order":"1", "filter_mode":"include", "include_regex":["^DE backup$"]}
 ]
}
JSON
ucode -L "$LIB" "$LIB/singbox/generator.uc" generate-config-fixture "$WORK_DIR/config.json" "$WORK_DIR/generated.json" 127.0.0.1
ucode -e '
let fs = require("fs");
let cfg = json(fs.readfile(ARGV[0]));
let cache = json(fs.readfile(ARGV[1]));
let group = cache.priorityGroups["chat-priority-group-out"];
if (!group || length(group.levels) != 2 || length(group.levels[0].outbounds) != 0 || length(group.levels[1].outbounds) != 1)
    die("configured standby did not survive a missing primary\n");
let selector = null;
for (let o in cfg.outbounds) if (o.tag == "chat-priority-group-out") selector = o;
if (!selector || length(selector.outbounds) != 1 || selector.outbounds[0] != group.levels[1].outbounds[0])
    die("the selector did not retain only the configured backup\n");
if (selector.outbounds[0] == "direct-out") die("unexpected direct fallback\n");
' "$WORK_DIR/generated.json" "$WORK_DIR/generated.json.section-cache/chat.json"

# Health-based selection respects level order, then the explicitly named backup.
cat >"$WORK_DIR/group.json" <<'JSON'
{"levels":[{"name":"Primary","order":0,"outbounds":["main"]},{"name":"Backup","order":1,"outbounds":["backup"]}]}
JSON
printf '%s\n' '{"main":200,"backup":100}' >"$WORK_DIR/up.json"
printf '%s\n' '{"main":-1,"backup":100}' >"$WORK_DIR/down.json"
ucode -L "$LIB" "$LIB/singbox/priority.uc" select-fixture "$WORK_DIR/group.json" "$WORK_DIR/up.json" 0 1 >"$WORK_DIR/selected-up.json"
ucode -L "$LIB" "$LIB/singbox/priority.uc" select-fixture "$WORK_DIR/group.json" "$WORK_DIR/down.json" 0 1 >"$WORK_DIR/selected-down.json"
ucode -e '
let fs = require("fs");
if (json(fs.readfile(ARGV[0])).tag != "main" || json(fs.readfile(ARGV[1])).tag != "backup")
    die("priority selection did not use primary then backup\n");
' "$WORK_DIR/selected-up.json" "$WORK_DIR/selected-down.json"
printf 'priority backup selection checks passed\n'
