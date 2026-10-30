#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORKOP_LIB="$ROOT_DIR/forkop/files/usr/lib"
GENERATOR_UC="$FORKOP_LIB/singbox/generator.uc"
WORK_DIR="$(mktemp -d)"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

generate() {
  ucode -L "$FORKOP_LIB" "$GENERATOR_UC" generate-config-fixture "$1" "$2" 127.0.0.1
}

# A group which loses every leaf to its filter must fail while the config is
# still staged.  It may never be represented by final/direct.
cat >"$WORK_DIR/urltest-empty.json" <<'JSON'
{
  "settings": { ".name": "settings", ".type": "settings" },
  "section": [{
    ".name": "proxy", ".type": "section", "enabled": "1", "action": "connection",
    "selector_proxy_links": ["vless://00000000-0000-4000-8000-000000000001@edge.example:443?encryption=none&security=tls&sni=edge.example&type=ws#Only%20leaf"]
  }],
  "urltest": [{
    ".name": "ut_empty", ".type": "urltest", "section": "proxy", "name": "Empty URLTest",
    "filter_mode": "include", "include_regex": ["^does-not-match$"]
  }]
}
JSON

if generate "$WORK_DIR/urltest-empty.json" "$WORK_DIR/urltest-empty-config.json" >"$WORK_DIR/urltest-empty.out" 2>"$WORK_DIR/urltest-empty.err"; then
  fail "URLTest with zero usable leaves was accepted"
fi
grep -Fq "URLTest group 'Empty URLTest'" "$WORK_DIR/urltest-empty.out" "$WORK_DIR/urltest-empty.err" &&
  grep -Fq 'has no usable proxy outbounds after filtering' "$WORK_DIR/urltest-empty.out" "$WORK_DIR/urltest-empty.err" ||
  fail "empty URLTest did not report the fail-closed reason"
grep -Fq 'filter mode: include' "$WORK_DIR/urltest-empty.out" "$WORK_DIR/urltest-empty.err" &&
  grep -Fq 'Only leaf' "$WORK_DIR/urltest-empty.out" "$WORK_DIR/urltest-empty.err" ||
  fail "empty URLTest did not report its filter and available server name"
if grep -Fq '00000000-0000-4000-8000-000000000001' "$WORK_DIR/urltest-empty.out" "$WORK_DIR/urltest-empty.err"; then
  fail "empty URLTest diagnostics exposed a proxy credential"
fi

# Provider-supplied labels can themselves contain credentials or addresses.
cat >"$WORK_DIR/urltest-private-names.json" <<'JSON'
{
  "settings": { ".name": "settings", ".type": "settings" },
  "section": [{
    ".name": "proxy", ".type": "section", "enabled": "1", "action": "connection",
    "selector_proxy_links": [
      "vless://00000000-0000-4000-8000-000000000001@edge.example:443?encryption=none&security=tls&sni=edge.example&type=ws#12345678-1234-1234-1234-123456789abc",
      "vless://00000000-0000-4000-8000-000000000002@edge.example:443?encryption=none&security=tls&sni=edge.example&type=ws#token-Private123",
      "vless://00000000-0000-4000-8000-000000000003@edge.example:443?encryption=none&security=tls&sni=edge.example&type=ws#192.0.2.45",
      "vless://00000000-0000-4000-8000-000000000004@edge.example:443?encryption=none&security=tls&sni=edge.example&type=ws#DE%20backup"
    ]
  }],
  "urltest": [{
    ".name": "ut_private", ".type": "urltest", "section": "proxy", "name": "Filtered",
    "filter_mode": "include", "include_regex": ["^does-not-match$"]
  }]
}
JSON
if generate "$WORK_DIR/urltest-private-names.json" "$WORK_DIR/urltest-private-config.json" >"$WORK_DIR/private.out" 2>"$WORK_DIR/private.err"; then
  fail "URLTest with zero usable leaves was accepted"
fi
grep -Fq '[name hidden]' "$WORK_DIR/private.out" "$WORK_DIR/private.err" &&
  grep -Fq 'DE backup' "$WORK_DIR/private.out" "$WORK_DIR/private.err" ||
  fail "URLTest diagnostics did not mask sensitive names or preserve a safe name"
hidden_count=$(grep -hFo '[name hidden]' "$WORK_DIR/private.out" "$WORK_DIR/private.err" | wc -l)
[ "$hidden_count" -eq 1 ] || fail "identical redacted names were not deduplicated"
for secret in '12345678-1234-1234-1234-123456789abc' 'token-Private123' '192.0.2.45'; do
  if grep -Fq "$secret" "$WORK_DIR/private.out" "$WORK_DIR/private.err"; then
    fail "URLTest diagnostics exposed a sensitive candidate name"
  fi
done

cat >"$WORK_DIR/priority-empty.json" <<'JSON'
{
  "settings": { ".name": "settings", ".type": "settings" },
  "section": [{
    ".name": "proxy", ".type": "section", "enabled": "1", "action": "connection",
    "selector_proxy_links": ["vless://00000000-0000-4000-8000-000000000001@edge.example:443?encryption=none&security=tls&sni=edge.example&type=ws#Only%20leaf"]
  }],
  "priority_group": [{
    ".name": "pg_empty", ".type": "priority_group", "section": "proxy", "name": "Empty Priority"
  }],
  "priority_level": [{
    ".name": "pl_empty", ".type": "priority_level", "group": "pg_empty", "name": "No matches",
    "order": "0", "filter_mode": "include", "include_regex": ["^does-not-match$"]
  }]
}
JSON

if generate "$WORK_DIR/priority-empty.json" "$WORK_DIR/priority-empty-config.json" >"$WORK_DIR/priority-empty.out" 2>"$WORK_DIR/priority-empty.err"; then
  fail "Priority group with zero usable leaves was accepted"
fi
grep -Fq "Priority group 'Empty Priority'" "$WORK_DIR/priority-empty.out" "$WORK_DIR/priority-empty.err" &&
  grep -Fq 'has no usable proxy outbounds after filtering' "$WORK_DIR/priority-empty.out" "$WORK_DIR/priority-empty.err" ||
  fail "empty Priority group did not report the fail-closed reason"

printf 'empty URLTest/Priority group checks passed\n'
