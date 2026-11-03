const fs = require('fs');
const cp = require('child_process');
const path = require('path');
const assert = require('assert');
const source = fs.readFileSync('install.sh', 'utf8');
const fn = source.match(/prepare_artak_xray\(\) \{[\s\S]*?\n\}/)[0].replaceAll('/usr/bin/xray', '/nonexistent/artak-test-xray');
const shell = process.env.ARTAK_TEST_SH || (process.platform === 'win32' ? path.resolve(path.dirname(cp.execFileSync('where.exe', ['git'], {encoding:'utf8'}).trim().split(/\r?\n/)[0]), '../usr/bin/sh.exe') : '/bin/sh');
function run(mode) {
 const script = `PATH=/usr/bin:/bin; export PATH
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT
command_exists() { return 0; }
chmod() { return 0; }
fail() { echo "FAIL: $*"; exit 1; }
download_with_retry() { printf archive > "$2"; }
sha256sum() { if [ '${mode}' = bad ]; then printf '%064d  file\\n' 0; else echo '1811c8f1da0c3b6dc707ebaf1c8390e987ba39859a8f0a7aadd8526157f2ec8d file'; fi; }
unzip() { case "$3" in xray) printf '#!/bin/sh\\nexit 0\\n' ;; *) printf data ;; esac; }
${fn}
prepare_artak_xray
[ -s "$XRAY_STAGED" ] && [ -s "$TMP_DIR/geoip.dat" ] && [ -s "$TMP_DIR/geosite.dat" ] && echo PASS`;
 return cp.spawnSync(shell, ['-c', script], {encoding:'utf8'});
}
const ok = run('ok'); assert.strictEqual(ok.status, 0, ok.stdout + ok.stderr); assert(ok.stdout.includes('PASS'));
const bad = run('bad'); assert.notStrictEqual(bad.status, 0, bad.stdout + bad.stderr); assert(bad.stdout.includes('checksum mismatch'));
const main = source.slice(source.indexOf('main() {'));
assert(main.indexOf('prepare_artak_xray') < main.indexOf('cleanup_legacy_installation'));
assert(main.indexOf('install_artak_xray') < main.indexOf('post_install'));
console.log('Xray staging and checksum failure: PASS');

