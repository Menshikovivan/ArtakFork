const fs=require('fs'),cp=require('child_process'),path=require('path'),assert=require('assert');
const src=fs.readFileSync('install.sh','utf8');const fn=src.match(/check_artak_uci_clean\(\) \{[\s\S]*?\n\}/)[0];
const sh=process.env.ARTAK_TEST_SH||(process.platform==='win32'?path.resolve(path.dirname(cp.execFileSync('where.exe',['git'],{encoding:'utf8'}).trim().split(/\r?\n/)[0]),'../usr/bin/sh.exe'):'/bin/sh');
function run(mode){return cp.spawnSync(sh,['-c',`command_exists() { return 0; }
fail() { echo "$1"; exit 1; }
uci() { case '${mode}' in clean) return 0;; pending) echo 'secret=value';; error) return 1;; esac; }
${fn}
check_artak_uci_clean
echo PASS`],{encoding:'utf8'});}
assert.strictEqual(run('clean').status,0);const bad=run('pending');assert.notStrictEqual(bad.status,0);assert(!bad.stdout.includes('secret=value'));assert.notStrictEqual(run('error').status,0);
const main=src.slice(src.indexOf('main() {'));assert(main.indexOf('check_artak_uci_clean')<main.indexOf('cleanup_legacy_installation'));
console.log('Pending UCI changes block upgrade without exposing values: PASS');
