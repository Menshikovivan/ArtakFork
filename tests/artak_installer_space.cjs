const fs=require('fs'), cp=require('child_process'), path=require('path'), assert=require('assert');
const src=fs.readFileSync('install.sh','utf8');
const fn=src.match(/check_artak_free_space\(\) \{[\s\S]*?\n\}/)[0];
const sh=process.env.ARTAK_TEST_SH || (process.platform==='win32' ? path.resolve(path.dirname(cp.execFileSync('where.exe',['git'],{encoding:'utf8'}).trim().split(/\r?\n/)[0]),'../usr/bin/sh.exe') : '/bin/sh');
function run(tmp,root){const script=`PATH=/usr/bin:/bin; export PATH
fail() { echo "FAIL: $*"; exit 1; }
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\\n'; case "$2" in /tmp) printf 'tmpfs 300000 1 ${tmp} 1%% /tmp\\n' ;; *) printf 'root 300000 1 ${root} 1%% /\\n' ;; esac; }
${fn}
check_artak_free_space
echo PASS`;
return cp.spawnSync(sh,['-c',script],{encoding:'utf8'});}
assert.strictEqual(run(120000,100000).status,0);
assert.notStrictEqual(run(100000,100000).status,0);
assert.notStrictEqual(run(120000,60000).status,0);
assert.notStrictEqual(run('bad',100000).status,0);
const main=src.slice(src.indexOf('main() {'));
assert(main.indexOf('check_artak_free_space') < main.indexOf('cleanup_legacy_installation'));
console.log('Free space guards before installation: PASS');
