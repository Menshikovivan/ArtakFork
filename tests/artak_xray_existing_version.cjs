const fs=require('fs'),cp=require('child_process'),path=require('path'),assert=require('assert');
const src=fs.readFileSync('install.sh','utf8');
const fn=src.match(/prepare_artak_xray\(\) \{[\s\S]*?\n\}/)[0].replace('[ -x /usr/bin/xray ]','[ "$XRAY_EXISTS" = 1 ]').replace('/usr/bin/xray version','fake_xray version');
const sh=process.env.ARTAK_TEST_SH||(process.platform==='win32'?path.resolve(path.dirname(cp.execFileSync('where.exe',['git'],{encoding:'utf8'}).trim().split(/\r?\n/)[0]),'../usr/bin/sh.exe'):'/bin/sh');
function run(version){return cp.spawnSync(sh,['-c',`XRAY_EXISTS=1
fail() { echo "$1"; exit 1; }
head() { IFS= read -r line; printf "%s\\n" "$line"; }
fake_xray() { printf '%s\\n' '${version}'; }
${fn}
prepare_artak_xray
printf PASS`],{encoding:'utf8'});}
assert.strictEqual(run('Xray 26.10.31 (Xray)').status,0);
assert.notStrictEqual(run('Xray 1.8.0 (Xray)').status,0);
assert.notStrictEqual(run('unexpected output').status,0);
console.log('Existing untested Xray version rejected before package changes: PASS');
