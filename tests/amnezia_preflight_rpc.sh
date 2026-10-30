#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/forkop/files/usr/lib"
RPC="$LIB/subscription/amnezia_preflight_rpc.uc"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ucode -L "$LIB" "$RPC" list > "$WORK/list.json"
python3 - "$WORK" <<'PY'
import json, os, sys
w = sys.argv[1]
assert json.load(open(os.path.join(w, 'list.json'))) == {'preflight': {'config': ''}}
key = 'A' * 43 + '='
conf = '[Interface]\nPrivateKey = ' + key + '\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = ' + key + '\nEndpoint = example.com:443\nAllowedIPs = 0.0.0.0/0\n'
for name, value in [('good', conf), ('bad', conf + 'PostUp = DO_NOT_LEAK_SECRET\n'), ('large', 'x' * 262145)]:
    with open(os.path.join(w, name + '.json'), 'w') as f: json.dump({'config': value}, f)
PY
for name in good bad large; do
  ucode -L "$LIB" "$RPC" call preflight < "$WORK/$name.json" > "$WORK/$name.out"
done
python3 - "$WORK" <<'PY'
import json, os, sys
w = sys.argv[1]
for name in ('good', 'bad', 'large'):
    text = open(os.path.join(w, name + '.out')).read()
    obj = json.loads(text)
    assert obj['ok'] == (name == 'good'), (name, obj)
    assert 'DO_NOT_LEAK_SECRET' not in text and 'A' * 43 + '=' not in text
assert json.load(open(os.path.join(w, 'good.out')))['peer_count'] == 1
PY
echo 'AmneziaWG preflight RPC stdin and size checks passed'
