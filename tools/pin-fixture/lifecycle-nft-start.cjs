// Execute the real startup guard with the rebuild and engine mocked.
const fs=require('fs'),assert=require('assert');
const source=fs.readFileSync('forkop/files/usr/lib/service/lifecycle.uc','utf8');
const m=source.match(/    status = nft_rebuild_runtime\(\);[^]*?    sync_excluded_dns\(\);/);
assert(m,'startup rebuild block missing');
function run(xray, code) {
  let synced=false,logs=[];
  const fn=new Function('nft_rebuild_runtime','engine','log_message','sync_excluded_dns',
    `let status=0; ${m[0]} return 0;`);
  const result=fn(()=>code,{is_xray_primary:()=>xray},(message,level)=>logs.push([message,level]),()=>{synced=true;});
  return {result,synced,logs};
}
let r=run(true,1);assert.strictEqual(r.result,1);assert(!r.synced);assert(r.logs.some(x=>x[1]==='fatal'));
r=run(true,0);assert.strictEqual(r.result,0);assert(r.synced);
r=run(false,1);assert.strictEqual(r.result,0);assert(r.synced);assert(r.logs.some(x=>x[1]==='warn'));
console.log('PASS: Xray startup rejects nft rebuild failure; sing-box behavior retained');
