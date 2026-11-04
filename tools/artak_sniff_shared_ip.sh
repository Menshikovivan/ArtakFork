#!/bin/sh
# Isolated Xray HTTP sniffing test: synthetic hostnames, one numeric IP.
# Usage: sh artak_sniff_shared_ip.sh /path/to/xray [SOCKS_PORT] [HTTP_PORT]
set -u
[ "$#" -ge 1 ] && [ "$#" -le 3 ] || { echo 'Usage: XRAY [SOCKS_PORT] [HTTP_PORT]' >&2; exit 2; }
xray=$1; socks=${2:-38782}; http=${3:-38783}
[ -x "$xray" ] || exit 2
for port in "$socks" "$http"; do
    case "$port" in ''|*[!0-9]*) exit 2 ;; esac
    [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] || exit 2
done
[ "$socks" != "$http" ] || exit 2
for command_name in curl uhttpd netstat awk grep; do command -v "$command_name" >/dev/null 2>&1 || exit 2; done
listeners=$(netstat -lnt 2>/dev/null) || exit 2
for port in "$socks" "$http"; do
    if printf '%s\n' "$listeners" | awk -v suffix=":$port" 'NR > 2 && substr($4,length($4)-length(suffix)+1)==suffix { found=1 } END { exit !found }'; then
        echo 'An isolated test port is already in use.' >&2; exit 2
    fi
done
umask 077
work=$(mktemp -d /tmp/artak-sniff-probe.XXXXXX) || exit 1
www=$(mktemp -d /tmp/artak-sniff-www.XXXXXX) || { rm -rf "$work"; exit 1; }
server_pid=''; xray_pid=''
cleanup() {
    for pid in "$xray_pid" "$server_pid"; do
        [ -n "$pid" ] || continue
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    rm -rf "$work" "$www"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
chmod 0755 "$www" || exit 1
printf 'artak-test\n' > "$www/index.html" || exit 1
chmod 0644 "$www/index.html" || exit 1
uhttpd -f -p "127.0.0.1:$http" -h "$www" >"$work/http.log" 2>&1 & server_pid=$!
sleep 1
kill -0 "$server_pid" 2>/dev/null || { echo 'Test HTTP server did not start.' >&2; exit 1; }
direct_code=$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 3 --max-time 5 \
    --noproxy '*' "http://127.0.0.1:$http/" 2>/dev/null) && direct_status=0 || direct_status=$?
if [ "$direct_status" -ne 0 ] || [ "$direct_code" != 200 ]; then
    printf 'Test HTTP server check failed: curl_exit=%s http=%s\n' "$direct_status" "$direct_code" >&2
    exit 1
fi

start_xray() {
    enabled=$1; route_only=$2
    cat > "$work/config.json" <<EOF
{"log":{"access":"$work/access.log","error":"none","loglevel":"warning"},
 "dns":{"hosts":{"alpha.artak.invalid":"127.0.0.2","beta.artak.invalid":"127.0.0.2"},"servers":["localhost"]},
 "inbounds":[{"tag":"probe","listen":"127.0.0.1","port":$socks,"protocol":"socks","settings":{"auth":"noauth","udp":false},
              "sniffing":{"enabled":$enabled,"destOverride":["http"],"routeOnly":$route_only}}],
 "outbounds":[{"tag":"fallback","protocol":"freedom","settings":{"domainStrategy":"UseIP"}},
              {"tag":"alpha","protocol":"freedom","settings":{"domainStrategy":"UseIP"}},
              {"tag":"beta","protocol":"freedom","settings":{"domainStrategy":"UseIP"}}],
 "routing":{"domainStrategy":"AsIs","rules":[
   {"type":"field","inboundTag":["probe"],"domain":["full:alpha.artak.invalid"],"outboundTag":"alpha"},
   {"type":"field","inboundTag":["probe"],"domain":["full:beta.artak.invalid"],"outboundTag":"beta"},
   {"type":"field","inboundTag":["probe"],"outboundTag":"fallback"}]}}
EOF
    "$xray" run -test -c "$work/config.json" >"$work/xray.log" 2>&1 || return 1
    : > "$work/access.log"
    "$xray" run -c "$work/config.json" >"$work/xray.log" 2>&1 & xray_pid=$!
    sleep 2
    kill -0 "$xray_pid" 2>/dev/null
}

stop_xray() {
    kill "$xray_pid" 2>/dev/null || true
    wait "$xray_pid" 2>/dev/null || true
    xray_pid=''
}

probe() {
    host=$1; outbound=$2; expect_http=$3
    : > "$work/access.log"
    code=$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 4 --max-time 10 \
        --noproxy '' --socks5 "127.0.0.1:$socks" -H "Host: $host" "http://127.0.0.1:$http/" 2>/dev/null) && status=0 || status=$?
    if ! kill -0 "$xray_pid" 2>/dev/null || ! kill -0 "$server_pid" 2>/dev/null; then
        printf 'Probe %s: test process exited; curl_exit=%s http=%s\n' "$host" "$status" "$code" >&2
        return 1
    fi
    actual=none
    log_bytes=$(wc -c < "$work/access.log" 2>/dev/null || printf 0)
    for candidate in alpha beta fallback; do
        if grep -Fq "[probe -> $candidate]" "$work/access.log" 2>/dev/null ||
           grep -Fq "[probe ==> $candidate]" "$work/access.log" 2>/dev/null ||
           grep -Fq "[probe >> $candidate]" "$work/access.log" 2>/dev/null; then
            actual=$candidate
            break
        fi
    done
    if [ "$expect_http" = success ]; then
        if [ "$status" -ne 0 ] || [ "$code" != 200 ] || [ "$actual" != "$outbound" ]; then
            printf 'Probe %s: curl_exit=%s http=%s expected_route=%s observed_route=%s log_bytes=%s\n' "$host" "$status" "$code" "$outbound" "$actual" "$log_bytes" >&2
            return 1
        fi
    else
        if [ "$status" -eq 0 ] || [ "$code" != 000 ] || [ "$actual" != "$outbound" ]; then
            printf 'Probe %s: curl_exit=%s http=%s expected_route=%s observed_route=%s log_bytes=%s\n' "$host" "$status" "$code" "$outbound" "$actual" "$log_bytes" >&2
            return 1
        fi
    fi
    return 0
}

start_xray true true || { echo 'Xray did not start (routeOnly=true).' >&2; exit 1; }
probe alpha.artak.invalid alpha success && probe beta.artak.invalid beta success || {
    echo 'Sniffed HTTP domains did not select their separate outbounds.' >&2; exit 1;
}
echo 'Shared IP, sniffing enabled, routeOnly=true: distinct routes and HTTP 200 PASS'
stop_xray
start_xray false true || { echo 'Xray did not start (sniffing=false).' >&2; exit 1; }
probe alpha.artak.invalid fallback success && probe beta.artak.invalid fallback success || {
    echo 'No-sniffing negative control failed.' >&2; exit 1;
}
echo 'Shared IP, sniffing disabled: both use fallback PASS'
stop_xray
start_xray true false || { echo 'Xray did not start (routeOnly=false).' >&2; exit 1; }
probe alpha.artak.invalid alpha failure && probe beta.artak.invalid beta failure || {
    echo 'routeOnly=false destination replacement control failed.' >&2; exit 1;
}
echo 'routeOnly=false: synthetic domains resolved to the non-listening IP PASS'
echo 'HTTP sniffing test complete; TLS SNI and TPROXY remain untested.'
