const fs = require('fs');
const cp = require('child_process');
const assert = require('assert');
const src = fs.readFileSync('install.sh','utf8');
const fn = src.match(/download_artak_srs\(\) \{[\s\S]*?\n\}/)[0];
const path = require('path');
const shell = process.env.ARTAK_TEST_SH || (process.platform === 'win32'
  ? path.resolve(path.dirname(cp.execFileSync('where.exe', ['git'], {encoding:'utf8'}).trim().split(/\\r?\\n/)[0]), '../usr/bin/sh.exe')
  : '/bin/sh');
function run(mode) {
 const script = `PATH=/usr/bin:/bin; export PATH
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT
REPO_OWNER=test; REPO_NAME=test; FORKOP_RELEASE_TAG=1.2.3
uname() { echo aarch64; }
command_exists() { return 0; }
sha256sum() { printf "%064d  file\\n" 1; }
fail() { echo "FAIL: $*"; exit 1; }
download_with_retry() { case "$2" in *.sha256) if [ "${mode}" = bad ]; then printf '%064d  file\\n' 0 > "$2"; else sha256sum "$TMP_DIR/artak-srs-linux-arm64" > "$2"; fi ;; *) printf data > "$2" ;; esac; }
${fn}
download_artak_srs
printf 'PASS\\n'`;
 return cp.spawnSync(shell, ['-c',script], {encoding:'utf8'});
}
const good = run('good'); assert.strictEqual(good.status,0,good.stdout+good.stderr); assert(good.stdout.includes('PASS'));
const bad = run('bad'); assert.notStrictEqual(bad.status,0,bad.stdout+bad.stderr); assert(bad.stdout.includes('checksum mismatch'));
console.log('Installer checksum success and tamper rejection: PASS');


