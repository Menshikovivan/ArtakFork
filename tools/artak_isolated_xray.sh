#!/bin/sh
# Usage: sh artak_isolated_xray.sh CONFIG XRAY HTTPS_URL auto
# Or supply EXPECTED_TAG [exact|prefix] after independently verifying it.
# CONFIG must be a protected generated copy, never the running configuration.
set -u
[ "$#" -ge 4 ] && [ "$#" -le 5 ] || { echo 'Usage: CONFIG XRAY HTTPS_URL EXPECTED_TAG [exact|prefix]' >&2; exit 2; }
config=$1; xray=$2; url=$3; expected=$4; match_mode=${5:-exact}
case "$config" in /tmp/*) ;; *) echo 'Use an isolated configuration copy under /tmp.' >&2; exit 2 ;; esac
case "$match_mode" in exact|prefix) ;; *) exit 2 ;; esac
[ -n "$expected" ] && [ -f "$config" ] && [ -x "$xray" ] || exit 2
# Limit probes to a GET on a hostname, not arbitrary paths or tokens.
printf '%s\n' "$url" | grep -Eq '^https://[A-Za-z0-9.-]+/?$' || exit 2
command -v curl >/dev/null 2>&1 && command -v ucode >/dev/null 2>&1 || exit 2
command -v netstat >/dev/null 2>&1 || exit 2
port=${ARTAK_TEST_PORT:-38781}
case "$port" in ''|*[!0-9]*) exit 2 ;; esac
listeners=$(netstat -lnt 2>/dev/null) || { echo 'Unable to check test port.' >&2; exit 2; }
if printf '%s\n' "$listeners" | awk -v suffix=":$port" 'NR > 2 && substr($4,length($4)-length(suffix)+1)==suffix { found=1 } END { exit !found }'; then
    echo 'Test port is already in use.' >&2; exit 2
fi
umask 077
work=$(mktemp -d /tmp/artak-xray-probe.XXXXXX) || exit 1
pid=''
cleanup() {
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
helper="$script_dir/artak_isolated_xray.uc"
if [ "$expected" = auto ]; then
    host=${url#https://}; host=${host%/}
    ucode "$script_dir/artak_isolated_expected.uc" "$config" "$host" "$work/expected.json" >/dev/null 2>&1 || {
        echo 'Cannot infer the route unambiguously; provide an independently verified outbound tag.' >&2; exit 1;
    }
fi

probe() {
    mode=$1
    ucode "$helper" "$config" "$work/config.json" "$port" "$work/access.log" "$mode" >/dev/null 2>&1 || return 1
    "$xray" run -test -c "$work/config.json" >"$work/xray.log" 2>&1 || return 1
    "$xray" run -c "$work/config.json" >"$work/xray.log" 2>&1 & pid=$!
    # A collision or startup failure must not be mistaken for a working proxy.
    sleep 2
    kill -0 "$pid" 2>/dev/null || return 1
    code=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --connect-timeout 8 --max-time 20 --noproxy '' \
        --socks5-hostname "127.0.0.1:$port" "$url" 2>/dev/null) && status=0 || status=$?
    kill -0 "$pid" 2>/dev/null || return 1
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    pid=''
    if [ "$mode" = negative ]; then
        [ "$status" -ne 0 ] && [ "$code" = 000 ]
        return $?
    fi
    [ "$status" -eq 0 ] && [ "$code" != 000 ] || return 1
    ARTAK_LOG="$work/access.log" ARTAK_EXPECTED="$expected" ARTAK_MODE="$match_mode" ARTAK_ALLOWED="$work/expected.json" ucode -e '
      let f=require("fs"), data=f.readfile(getenv("ARTAK_LOG"));
      let expected=getenv("ARTAK_EXPECTED"), mode=getenv("ARTAK_MODE"), allowed=[];
      if (data == null || expected == "") exit(1);
      if (expected == "auto") {
        let contents=f.readfile(getenv("ARTAK_ALLOWED"));
        allowed=contents == null ? null : json(contents);
        if (type(allowed) != "array" || length(allowed) == 0) exit(1);
      }
      let ok=false;
      for (let line in split(data,"\n")) {
        for (let arrow in [" -> ", " ==> ", " >> "]) {
          let marker="[artak-isolated-test"+arrow, pos=index(line,marker);
          if (pos < 0) continue;
          let rest=substr(line,pos+length(marker));
          let end=index(rest,"]"); if (end < 0) continue;
          let tag=substr(rest,0,end);
          if ((expected == "auto" && index(allowed,tag) >= 0) ||
              (expected != "auto" && mode == "exact" && tag == expected) ||
              (expected != "auto" && mode == "prefix" && index(tag,expected) == 0)) ok=true;
        }
      }
      if (!ok) exit(1);
    ' >/dev/null 2>&1 || return 1
    printf 'Proxy connection: HTTP %s; selected outbound matched.\n' "$code"
}

probe negative || { echo 'Negative control failed; no positive result accepted.' >&2; exit 1; }
echo 'Negative control: PASS'
: > "$work/access.log"
probe positive || { echo 'Proxy probe failed or selected outbound did not match.' >&2; exit 1; }
echo 'Isolated Xray domain route: PASS'
