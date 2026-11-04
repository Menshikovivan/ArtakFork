const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const assert = require('assert');

const src = fs.readFileSync('install.sh', 'utf8');
const fn = src.match(/restore_artak_absent_artifacts\(\) \{[\s\S]*?\n\}/)[0]
  .replace('"/$artifact"', '"$TEST_ROOT/$artifact"');
const shell = process.env.ARTAK_TEST_SH || (process.platform === 'win32'
  ? path.resolve(path.dirname(cp.execFileSync('where.exe', ['git'], {encoding: 'utf8'}).trim().split(/\r?\n/)[0]), '../usr/bin/sh.exe')
  : '/bin/sh');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'artak-rollback-'));
try {
  const temp = path.join(root, 'new');
  const preserved = path.join(root, 'usr/libexec/artak-srs');
  const introduced = path.join(root, 'usr/bin/xray');
  const manifest = path.join(temp, 'absent');
  fs.mkdirSync(path.dirname(preserved), {recursive: true});
  fs.mkdirSync(path.dirname(introduced), {recursive: true});
  fs.mkdirSync(temp);
  fs.writeFileSync(preserved, 'previous converter');
  fs.writeFileSync(introduced, 'new xray');
  fs.writeFileSync(manifest, 'usr/bin/xray\n');
  const run = () => cp.spawnSync(shell, ['-c', `${fn}\nrestore_artak_absent_artifacts`], {
    encoding: 'utf8', env: {...process.env, TEST_ROOT: root, artak_absent_file: manifest}
  });
  let result = run();
  assert.strictEqual(result.status, 0, result.stdout + result.stderr);
  assert(!fs.existsSync(introduced));
  assert.strictEqual(fs.readFileSync(preserved, 'utf8'), 'previous converter');
  assert.strictEqual(run().status, 0, 'cleanup must be idempotent');
  fs.writeFileSync(manifest, '../outside\n');
  assert.notStrictEqual(run().status, 0, 'unexpected paths must be rejected');
  fs.unlinkSync(manifest);
  assert.notStrictEqual(run().status, 0, 'missing inventory must be rejected');
  console.log('Rollback removes only newly introduced artifacts: PASS');
} finally {
  fs.rmSync(root, {recursive: true, force: true});
}
