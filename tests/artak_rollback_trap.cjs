const fs=require('fs'),cp=require('child_process'),path=require('path'),assert=require('assert');
const source=fs.readFileSync('install.sh','utf8');const fn=source.match(/installer_exit\(\) \{[\s\S]*?\n\}/)[0];
const sh=process.env.ARTAK_TEST_SH||(process.platform==='win32'?path.resolve(path.dirname(cp.execFileSync('where.exe',['git'],{encoding:'utf8'}).trim().split(/\r?\n/)[0]),'../usr/bin/sh.exe'):'/bin/sh');
function run(code,armed,restores){const script=`ARTAK_TXN_ARMED=${armed}; backup_file=/tmp/test
restore_artak_previous(){ echo RESTORE; return ${restores}; }
warn(){ echo WARN; }
cleanup(){ echo CLEANUP; }
${fn}
trap installer_exit EXIT
exit ${code}`;return cp.spawnSync(sh,['-c',script],{encoding:'utf8'});}
let fail=run(17,1,0);assert.strictEqual(fail.status,17);assert(fail.stdout.indexOf('RESTORE')<fail.stdout.indexOf('CLEANUP'));
let ok=run(0,1,0);assert.strictEqual(ok.status,0);assert(!ok.stdout.includes('RESTORE'));
let early=run(1,0,0);assert.strictEqual(early.status,1);assert(!early.stdout.includes('RESTORE'));
let broken=run(4,1,1);assert.strictEqual(broken.status,4);assert(broken.stdout.includes('WARN'));
console.log('Exit trap invokes rollback only after transaction starts: PASS');
