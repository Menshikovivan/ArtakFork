const fs = require('fs');
const cp = require('child_process');
const path = require('path');
const assert = require('assert');
const source = fs.readFileSync('install.sh','utf8');
const fn = source.match(/prepare_artak_community_lists\(\) \{[\s\S]*?\n\}/)[0].replace('[ -f /etc/config/forkop ] || return 0', ':');
const shell = process.env.ARTAK_TEST_SH || (process.platform === 'win32' ? path.resolve(path.dirname(cp.execFileSync('where.exe',['git'],{encoding:'utf8'}).trim().split(/\r?\n/)[0]), '../usr/bin/sh.exe') : '/bin/sh');
const script = `PATH=/usr/bin:/bin; export PATH
TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT
command_exists() { return 0; }
fail() { echo "FAIL: $*"; exit 1; }
install_json_ucode() { [ "$1" = artak-community-lists ] || return 1; printf 'youtube telegram meta\ndiscord telegram\n'; }
download_with_retry() { printf domain > "$2"; }
${fn}
prepare_artak_community_lists
for n in youtube telegram meta discord; do [ -s "$TMP_DIR/xray-lists/Services/$n.lst" ] || exit 2; done
for n in telegram meta discord; do for v in IPv4 IPv6; do [ -s "$TMP_DIR/xray-lists/Subnets/$v/$n.lst" ] || exit 3; done; done
[ ! -e "$TMP_DIR/xray-lists/Subnets/IPv4/youtube.lst" ] || exit 4
printf PASS`;
const result=cp.spawnSync(shell,['-c',script],{encoding:'utf8'});
assert.strictEqual(result.status,0,result.stdout+result.stderr);
assert(result.stdout.includes('PASS'));
const main=source.slice(source.indexOf('main() {'));
assert(main.indexOf('prepare_artak_community_lists') < main.indexOf('cleanup_legacy_installation'));
assert(main.indexOf('install_artak_community_lists') < main.indexOf('post_install'));
console.log('Community lists staged before package changes: PASS');
