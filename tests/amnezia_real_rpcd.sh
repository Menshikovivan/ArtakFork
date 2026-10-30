#!/bin/sh
# Real ubus/rpcd transport on Ubuntu. Worker is deliberately mocked: this
# does not test netifd, a real AWG interface, kernel routing or handshake.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
export ARTAK_AWG_JOB_TEST_DIR="$WORK/job" ARTAK_TEST_ROOT="$ROOT"
export ARTAK_TEST_BIN="$WORK/bin"
mkdir -p "$WORK/bin" "$ARTAK_TEST_PREFIX/libexec/rpcd"
cleanup() {
    [ -z "${RPCD_PID:-}" ] || kill "$RPCD_PID" 2>/dev/null || true
    [ -z "${UBUSD_PID:-}" ] || kill "$UBUSD_PID" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM
cp "$ROOT/luci-app-forkop/root/usr/libexec/rpcd/luci.artak_awg" "$ARTAK_TEST_PREFIX/libexec/rpcd/luci.artak_awg"
chmod 755 "$ARTAK_TEST_PREFIX/libexec/rpcd/luci.artak_awg"
cat > "$WORK/bin/ucode" <<'EOF'
#!/bin/sh
if [ "$3" = /usr/lib/forkop/subscription/amnezia_preflight_rpc.uc ]; then
    shift 3
    exec "$ARTAK_TEST_UCODE" -L "$ARTAK_TEST_UCODE_MODULES/*.so" -L "$ARTAK_TEST_ROOT/forkop/files/usr/lib" "$ARTAK_TEST_ROOT/forkop/files/usr/lib/subscription/amnezia_preflight_rpc.uc" "$@"
fi
if [ "$3" = /usr/lib/forkop/subscription/amnezia_job_worker.uc ]; then
    exec "$ARTAK_TEST_UCODE" -L "$ARTAK_TEST_UCODE_MODULES/*.so" -L "$ARTAK_TEST_ROOT/forkop/files/usr/lib" "$ARTAK_TEST_ROOT/tests/amnezia_mock_worker.uc"
fi
exit 1
EOF
chmod 755 "$WORK/bin/ucode"
export PATH="$WORK/bin:$ARTAK_TEST_PREFIX/bin:$PATH"
"$ARTAK_TEST_PREFIX/sbin/ubusd" -s "$WORK/ubus.sock" >"$WORK/ubusd.log" 2>&1 & UBUSD_PID=$!
for i in 1 2 3 4 5; do [ -S "$WORK/ubus.sock" ] && break; sleep 1; done
[ -S "$WORK/ubus.sock" ]
"$ARTAK_TEST_PREFIX/sbin/rpcd" -s "$WORK/ubus.sock" -t 10 >"$WORK/rpcd.log" 2>&1 & RPCD_PID=$!
for i in 1 2 3 4 5; do
    if "$ARTAK_TEST_PREFIX/bin/ubus" -s "$WORK/ubus.sock" list luci.artak_awg | grep -q luci.artak_awg; then break; fi
    sleep 1
done
python3 - "$WORK/request.json" <<'PY'
import json, sys
key = 'A' * 43 + '='
config = '[Interface]\nPrivateKey = '+key+'\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = '+key+'\nEndpoint = example.com:443\nAllowedIPs = 0.0.0.0/0\n'
with open(sys.argv[1], 'w') as f: json.dump({'config': config}, f)
PY
"$ARTAK_TEST_PREFIX/bin/ubus" -s "$WORK/ubus.sock" call luci.artak_awg preflight "$(cat "$WORK/request.json")" > "$WORK/preflight.json"
"$ARTAK_TEST_PREFIX/bin/ubus" -s "$WORK/ubus.sock" call luci.artak_awg import_conf "$(cat "$WORK/request.json")" > "$WORK/start.json"
"$ARTAK_TEST_PREFIX/bin/ubus" -s "$WORK/ubus.sock" call luci.artak_awg import_status '{}' > "$WORK/running.json"
sleep 5
"$ARTAK_TEST_PREFIX/bin/ubus" -s "$WORK/ubus.sock" call luci.artak_awg import_status '{}' > "$WORK/done.json"
python3 - "$WORK" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
read = lambda n: json.loads((p / (n + '.json')).read_text())
assert read('preflight')['ok']
assert read('start')['state'] == 'running'
assert read('running')['state'] == 'running'
assert read('done') == {'ok': True, 'state': 'done', 'name': 'afawg_1'}
for n in ('preflight', 'start', 'running', 'done'):
    assert 'A' * 43 + '=' not in (p / (n + '.json')).read_text()
assert not (p / 'job/input').exists()
PY
echo 'Real rpcd/ubus async transport passed with mock worker'
