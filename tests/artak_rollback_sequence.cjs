const fs=require('fs'),cp=require('child_process'),path=require('path'),assert=require('assert');
const src=fs.readFileSync('install.sh','utf8');
const fn=src.match(/restore_artak_previous\(\) \{[\s\S]*?\n\}/)[0].replaceAll('/etc/init.d/forkop','fake_init').replaceAll(' >/dev/null 2>&1','');
const sh=process.env.ARTAK_TEST_SH||(process.platform==='win32'?path.resolve(path.dirname(cp.execFileSync('where.exe',['git'],{encoding:'utf8'}).trim().split(/\r?\n/)[0]),'../usr/bin/sh.exe'):'/bin/sh');
function run(mode,ready=1){const script=`PATH=/usr/bin:/bin; export PATH
ARTAK_ROLLBACK_READY=${ready}; ARTAK_XRAY_NEW=0; ARTAK_PREVIOUS_ENABLED=1; ARTAK_PREVIOUS_RUNNING=1; TMP_DIR=/tmp/test; backup_file=/tmp/test.tar
apk() { if [ "$1" = info ]; then printf 'forkop-2.6.5\\nluci-app-forkop-2.6.5\\nluci-i18n-forkop-ru-2.6.5\\n'; else echo APK; [ '${mode}' != apkfail ]; fi; }
tar() { echo TAR; [ '${mode}' != tarfail ]; }
fake_init() { echo INIT:$1; [ '${mode}' != initfail ]; }
restore_artak_absent_artifacts() { echo CLEAN_ARTIFACTS; [ '${mode}' != artifactfail ]; }
${fn}
restore_artak_previous`;return cp.spawnSync(sh,['-c',script],{encoding:'utf8'});}
let ok=run('ok');assert.strictEqual(ok.status,0,ok.stdout+ok.stderr);assert(ok.stdout.indexOf('APK')<ok.stdout.indexOf('TAR'));assert(ok.stdout.includes('INIT:restart'));
for(const failure of ['apkfail','tarfail','initfail','artifactfail'])assert.notStrictEqual(run(failure).status,0,failure);
let no=run('ok',0);assert.notStrictEqual(no.status,0);assert.strictEqual(no.stdout,'');
const main=src.slice(src.indexOf('main() {'));for(const [a,b] of [['backup_artak_configuration','prepare_artak_rollback'],['prepare_artak_rollback','cleanup_legacy_installation'],['install_artak_xray',"artak-select-xray"],["artak-select-xray",'post_install'],['post_install','ARTAK_TXN_ARMED=0']])assert(main.indexOf(a)<main.indexOf(b),a+' before '+b);
console.log('Rollback sequencing and failure reporting: PASS');
