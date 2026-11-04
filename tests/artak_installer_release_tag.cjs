const fs = require('fs');
const cp = require('child_process');
const path = require('path');
const assert = require('assert');
const source = fs.readFileSync('install.sh', 'utf8');
const fn = name => source.match(new RegExp(name + '\\(\\) \\{[\\s\\S]*?\\n\\}'))[0];
const shell = process.env.ARTAK_TEST_SH || (process.platform === 'win32' ? path.resolve(path.dirname(cp.execFileSync('where.exe', ['git'], {encoding:'utf8'}).trim().split(/\r?\n/)[0]), '../usr/bin/sh.exe') : '/bin/sh');
function run(args, returnedTag='3.0.0') {
    const script = `ARTAK_REQUESTED_RELEASE_TAG=''; REPO_OWNER=Menshikovivan; REPO_NAME=ArtakFork; PKG_IS_APK=1; FORKOP_I18N_REQUESTED=0
fail(){ echo "FAIL:$*" >&2; exit 1; }
usage(){ :; }
http_get(){ case "$1" in https://api.github.com/repos/Menshikovivan/ArtakFork/releases/tags/3.0.0) echo '{"tag_name":"fixture"}' ;; *) return 1 ;; esac; }
install_json_ucode(){ case "$1" in github-message) : ;; release-tag) echo '${returnedTag}' ;; release-asset-url) case "$2" in backend) echo 'https://example.test/forkop_3.0.0.apk' ;; app) echo 'https://example.test/luci-app-forkop_3.0.0.apk' ;; esac ;; esac; }
${fn('parse_args')}
${fn('fetch_github_tagged_release_json')}
${fn('resolve_forkop_release')}
parse_args "$@"; resolve_forkop_release; echo "TAG:$FORKOP_RELEASE_TAG"`;
    const env = {...process.env};
    if (process.platform === 'win32') env.PATH = path.dirname(shell) + ';' + env.PATH;
    return cp.spawnSync(shell, ['-c', script, '_', ...args], {encoding:'utf8', env});
}
const valid = run(['--release-tag', '3.0.0']);
assert.strictEqual(valid.status, 0, valid.stdout + valid.stderr);
assert(!source.includes('/releases/latest'));
assert(valid.stdout.includes('TAG:3.0.0'));
for (const args of [[], ['--release-tag'], ['--release-tag', '../latest'], ['--release-tag', '3.0.0/other'], ['--release-tag','3.0.0','--release-tag','3.0.1']]) {
    const result = run(args);
    assert.notStrictEqual(result.status, 0, args.join(' '));
}
assert.notStrictEqual(run(['--release-tag', '3.0.0'], '2.0.0').status, 0, 'Mismatched release response must fail');
console.log('Installer requires and resolves an explicit numeric release tag: PASS');
