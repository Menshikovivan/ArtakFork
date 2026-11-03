const fs=require('fs'),cp=require('child_process'),path=require('path'),assert=require('assert');
const source=fs.readFileSync('install.sh','utf8');
const fn=source.match(/verify_artak_rollback_packages\(\) \{[\s\S]*?\n\}/)[0]+'\n'+source.match(/prepare_artak_rollback\(\) \{[\s\S]*?\n\}/)[0].replaceAll('/etc/init.d/forkop','fake_init').replace('[ -s "$backup_file" ]','[ "$BACKUP_VALID" = 1 ]');
const sh=process.env.ARTAK_TEST_SH||(process.platform==='win32'?path.resolve(path.dirname(cp.execFileSync('where.exe',['git'],{encoding:'utf8'}).trim().split(/\r?\n/)[0]),'../usr/bin/sh.exe'):'/bin/sh');
function run(mode){let script=`PATH=/usr/bin:/bin; export PATH
FORKOP_LEGACY_DETECTED=0; ARTAK_ROLLBACK_READY=0; ARTAK_PREVIOUS_RUNNING=0; ARTAK_PREVIOUS_ENABLED=0; PKG_IS_APK=1; TMP_DIR=/tmp/fake; BACKUP_VALID=1
pkg_is_installed() { [ "$1" = forkop ] && [ '${mode}' != fresh ]; }
fail() { echo FAIL:$1; exit 1; }
apk() { if [ '${mode}' = badversion ]; then echo forkop-9.9.9; else printf 'forkop-2.6.5\\nluci-app-forkop-2.6.5\\nluci-i18n-forkop-ru-2.6.5\\n'; fi; }
sha256sum() { [ '${mode}' != badhash ]; }
mkdir() { return 0; }
cp() { return 0; }
fake_init() { return 0; }
${fn}
prepare_artak_rollback
printf 'READY:%s RUNNING:%s ENABLED:%s\\n' "$ARTAK_ROLLBACK_READY" "$ARTAK_PREVIOUS_RUNNING" "$ARTAK_PREVIOUS_ENABLED"`;
return cp.spawnSync(sh,['-c',script],{encoding:'utf8'});}
let ok=run('good');assert.strictEqual(ok.status,0,ok.stdout+ok.stderr);assert(ok.stdout.includes('READY:1 RUNNING:1 ENABLED:1'));
for(const mode of ['badversion','badhash'])assert.notStrictEqual(run(mode).status,0,mode);
let fresh=run('fresh');assert.strictEqual(fresh.status,0);assert(fresh.stdout.includes('READY:0'));
console.log('Rollback preflight verifies supported version and packages: PASS');
