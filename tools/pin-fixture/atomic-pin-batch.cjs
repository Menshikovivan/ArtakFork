// Exercise the actual batch serializer and failure propagation with nft mocked.
const fs=require('fs'), assert=require('assert');
const source=fs.readFileSync('forkop/files/usr/lib/nft/apply.uc','utf8');
const m=source.match(/function nft_insert_pin_batch\([^]*?\n\}/);
assert(m,'batch helper missing');
const f=m[0].replace(/for \(let (args|part) in /g,'for (let $1 of ');
function run(commands,{failWrite=false,failNft=false,table='forkop'}={}) {
  let content='', calls=[], deleted=false;
  const build=new Function('length','as_string','append_array','match','log_debug','push','join',
    'trim','command_output_from_args','write_text_file','run_args_quiet','unlink_file',
    `${f}\nreturn nft_insert_pin_batch;`);
  const fn=build(v=>v.length,String,(a,b)=>{a.push(...b);},(s,re)=>s.match(re),()=>{},
    (a,v)=>a.push(v),(sep,a)=>a.join(sep),s=>s.trim(),()=>'/tmp/artak-test-file',
    (_,s)=>{content=s;return !failWrite;},args=>{calls.push(args);return !failNft;},
    ()=>{deleted=true;});
  return {ok:fn(table,commands),content,calls,deleted};
}
const cmd=['iifname','@lan','meta','mark','&','0x04000000','==','0x04000000',
  'ip','daddr','@forkop_rule_a_resolved','ip','daddr','!=','@forkop_rule_b_resolved',
  'meta','l4proto','tcp','tproxy','ip','to',':17020','counter','accept'];
const cmd6=['iifname','@lan','meta','mark','&','0x04000000','==','0x04000000',
  'ip6','daddr','@forkop_rule_a_resolved6','ip6','daddr','!=','@forkop_rule_b_resolved6',
  'meta','l4proto','udp','tproxy','ip6','to','[::1]:17020','counter','accept'];
let r=run([cmd,cmd6]);
assert(r.ok);assert.strictEqual(r.calls.length,1);assert.deepStrictEqual(r.calls[0],['nft','-f','/tmp/artak-test-file']);
assert.strictEqual(r.content.trim().split('\n').length,2);assert(r.deleted);
if(process.env.ARTAK_OUTPUT_NFT) fs.writeFileSync(process.env.ARTAK_OUTPUT_NFT,r.content);
r=run([cmd],{failNft:true});assert(!r.ok && r.deleted);
r=run([cmd],{failWrite:true});assert(!r.ok && r.deleted && !r.calls.length);
r=run([cmd],{table:'forkop;flush'});assert(!r.ok && !r.calls.length && !r.deleted);
console.log('PASS: single batch, insertion failure, write failure, token validation');
