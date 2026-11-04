const fs = require('fs');
const assert = require('assert');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const workflow = fs.readFileSync('.github/workflows/build.yml', 'utf8');
const action = workflow.replace(/\r\n/g, '\n').match(/- name: Release[ \t]*\n\s+uses: softprops\/action-gh-release@[^\n]+\n\s+with:([\s\S]*)/);
assert(action, 'release action must be present');
assert(/^\s+prerelease:\s*true\s*$/m.test(action[1]), 'Xray release must be a prerelease');
assert(/^\s+make_latest:\s*false\s*$/m.test(action[1]), 'Xray release must not become the latest stable release');
assert(!/^\s+prerelease:\s*false\s*$/m.test(action[1]), 'release must not silently become stable');
assert(workflow.includes('cp "$GITHUB_WORKSPACE/install.sh" artak-install.sh'), 'release must contain the installer');
for (const name of ['forkop_${VERSION}.apk', 'luci-app-forkop_${VERSION}.apk', 'luci-i18n-forkop-ru_${VERSION}.apk', 'forkop_${VERSION}.ipk', 'luci-app-forkop_${VERSION}.ipk', 'luci-i18n-forkop-ru_${VERSION}.ipk', 'artak-srs-linux-arm64', 'artak-srs-linux-arm64.sha256', 'artak-install.sh'])
  assert(workflow.includes(name), `missing release asset ${name}`);
assert(workflow.includes('sha256sum "${assets[@]}" > SHA256SUMS'), 'checksum manifest must cover all assets');
assert(workflow.includes('sha256sum -c SHA256SUMS'), 'release asset hashes must be verified');
const guard = workflow.replace(/\r\n/g, '\n').match(/( {10}# An existing tag must point[\s\S]*?\n {10}fi)\n/);
assert(guard, 'tag commit guard must be present');
const tagRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'artak-tags-'));
try {
  const runGit = (...args) => {
    const r = cp.spawnSync('git', ['-C', tagRoot, ...args], {encoding:'utf8'});
    assert.strictEqual(r.status, 0, r.stdout + r.stderr);
  };
  runGit('init');
  fs.writeFileSync(path.join(tagRoot, 'marker'), 'one');
  runGit('add', 'marker');
  runGit('-c','user.name=Artak test','-c','user.email=test@example.invalid','commit','-m','first');
  runGit('-c','user.name=Artak test','-c','user.email=test@example.invalid','tag','-a','3.0.0','-m','test');
  const tagShell = process.env.ARTAK_TEST_SH || (process.platform === 'win32' ? path.resolve(path.dirname(cp.execFileSync('where.exe',['git'],{encoding:'utf8'}).trim().split(/\r?\n/)[0]), '../usr/bin/sh.exe') : '/bin/bash');
  const tagEnv = {...process.env};
  if (process.platform === 'win32') tagEnv.PATH = path.dirname(tagShell) + ';' + tagEnv.PATH;
  const testTag = version => cp.spawnSync(tagShell, ['-e','-c', 'VERSION="$1"\n' + guard[1].replace(/^ {10}/gm,''), '_', version], {cwd:tagRoot, env:tagEnv, encoding:'utf8'});
  assert.strictEqual(testTag('3.0.0').status, 0, 'matching annotated tag should pass');
  fs.writeFileSync(path.join(tagRoot, 'marker'), 'two');
  runGit('add', 'marker');
  runGit('-c','user.name=Artak test','-c','user.email=test@example.invalid','commit','-m','second');
  assert.notStrictEqual(testTag('3.0.0').status, 0, 'tag pointing at another commit must fail');
  assert.strictEqual(testTag('3.0.1').status, 0, 'new tag should pass');
} finally { fs.rmSync(tagRoot, {recursive:true, force:true}); }
const step = workflow.replace(/\r\n/g, '\n').match(/- name: Prepare installer and checksums\n\s+shell: bash\n\s+run: \|\n((?: {10}.+\n|\n)+)/);
assert(step, 'checksum step must be extractable for testing');
const script = step[1].replace(/^ {10}/gm, '').replace('${{ needs.preparation.outputs.version }}', '3.0.0');
if (process.platform !== 'win32') {
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'artak-release-'));
try {
  const dir = path.join(root, 'filtered-bin', 'release');
  fs.mkdirSync(dir, {recursive: true});
  fs.writeFileSync(path.join(root, 'install.sh'), '#!/bin/sh\n');
  for (const name of ['forkop_3.0.0.apk','luci-app-forkop_3.0.0.apk','luci-i18n-forkop-ru_3.0.0.apk','forkop_3.0.0.ipk','luci-app-forkop_3.0.0.ipk','luci-i18n-forkop-ru_3.0.0.ipk','artak-srs-linux-arm64','artak-srs-linux-arm64.sha256']) fs.writeFileSync(path.join(dir, name), name);
  const shell = process.env.ARTAK_TEST_SH || (process.platform === 'win32' ? path.resolve(path.dirname(cp.execFileSync('where.exe',['git'],{encoding:'utf8'}).trim().split(/\r?\n/)[0]), '../usr/bin/sh.exe') : '/bin/bash');
  const env = {...process.env, GITHUB_WORKSPACE: process.platform === 'win32' ? '/' + root[0].toLowerCase() + root.slice(2).replace(/\\/g,'/') : root};
  if (process.platform === 'win32') env.PATH = path.dirname(shell) + ';' + env.PATH;
  const run = () => cp.spawnSync(shell, ['-e', '-c', script], {cwd:root, env, encoding:'utf8'});
  let result = run();
  assert.strictEqual(result.status, 0, result.stdout + result.stderr);
  assert.strictEqual(fs.readFileSync(path.join(dir, 'SHA256SUMS'), 'utf8').trim().split('\n').length, 9);
  fs.unlinkSync(path.join(dir, 'forkop_3.0.0.apk'));
  result = run();
  assert.notStrictEqual(result.status, 0, 'missing package must abort release preparation');
} finally { fs.rmSync(root, {recursive:true, force:true}); }
} else {
  console.log('Behavioral checksum test runs in Linux CI (sha256sum is unavailable in this Windows environment).');
}
console.log('Xray release is marked prerelease and is not latest: PASS');
