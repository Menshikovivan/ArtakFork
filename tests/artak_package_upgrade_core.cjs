const fs=require('fs'),assert=require('assert');
const s=fs.readFileSync('forkop/files/usr/lib/service/package.uc','utf8');
const f=s.match(/function prerm_cleanup\(action\) \{[\s\S]*?\n\}/)[0];
function run(action){let removed=0;const fn=new Function('env','remember_upgrade_state','PACKAGE_TEST_MODE','command_success_from_args','INIT_PATH','restore_dnsmasq_if_needed','remove_managed_sing_box','remove_rt_tables_entry','as_string',f+';return prerm_cleanup;')(()=>'',()=>{},false,()=>true,'init',()=>{},()=>removed++,()=>true,String);assert(fn(action));return removed;}
assert.strictEqual(run('upgrade'),0);
assert.strictEqual(run('remove'),1);
console.log('Upgrades retain existing managed core: PASS');
