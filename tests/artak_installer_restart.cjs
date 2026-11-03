const fs = require('fs');
const assert = require('assert');
const source = fs.readFileSync('install.sh','utf8');
const fn = source.match(/function installer_post_install\(\) \{[\s\S]*?\n\}/)[0].replace(/for \(let (\w+) in /g,'for (let $1 of ');
function run({running=true, present=true, start=true, restart=true, ready=true}={}) {
 let calls=[];
 const env=(key, fallback)=> key==='FORKOP_WAS_RUNNING' ? (running?'1':'0') : fallback;
 const run_args=args=>{calls.push(args[1]);return args[1]==='start'?start:args[1]==='restart'?restart:args[1]==='running'?ready:true;};
 const exec=new Function('remove_globs','env','words','remove_path','path_executable','INSTALLER_RPCD_INIT','INSTALLER_FORKOP_INIT','run_args','warn','system',fn+'; return installer_post_install;')(
  ()=>{},env,s=>s.split(' '),()=>{},p=>p==='forkop'&&present,'rpcd','forkop',run_args,()=>{},()=>0);
 return {result:exec(),calls};
}
assert.strictEqual(run({present:false}).result,false);
assert.strictEqual(run({start:false,restart:false}).result,false);
assert.strictEqual(run({start:false,restart:true}).result,true);
assert.strictEqual(run({running:false,present:false}).result,true);
const notReady=run({ready:false});
assert.strictEqual(notReady.result,false);
assert.strictEqual(notReady.calls.filter(x=>x==='running').length,90);
console.log('Installer reports failed service restart: PASS');
