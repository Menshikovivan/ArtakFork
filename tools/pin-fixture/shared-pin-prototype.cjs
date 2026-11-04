// Unit check of actual nft rule builders with synthetic sections and mocked nft.
const fs=require('fs'), assert=require('assert');
const text=fs.readFileSync('forkop/files/usr/lib/nft/apply.uc','utf8');
function extract(name) {
  const m=text.match(new RegExp(`function ${name}\\([^]*?\\n\\}`));
  assert(m, name+' missing');
  return m[0].replace(/for \(let section in sections\)/g,'for (let section of sections)');
}
const specs=[{name:'a',port:17020},{name:'b',port:17021}];
const sections=[{'.name':'a'},{'.name':'b'},{'.name':'c',kind:'ip-only'}];
function run(missing='') {
  const emitted=[];
  const b=new Function('engine','xray_constants','length','object_or_empty','as_string',
    'bool_option','section_needs_priority_sets','section_priority_sets','run_args_quiet',
    'append_array','core_ip','nft_insert_rule','log_info','log_debug',
    `${extract('nft_pin_exclusions')}\n${extract('nft_install_resolved_pin_tproxies')}\nreturn nft_install_resolved_pin_tproxies;`);
  const fn=b({is_xray_primary:()=>true}, {section_pin_specs:()=>specs,
    FAKEIP_INET4_RANGE:'198.18.0.0/15',FAKEIP_INET6_RANGE:'fc00::/18'},
    v=>v.length,v=>v||{},String,()=>true,()=>true,
    s=>{const p='forkop_rule_'+s['.name'];return {resolved:p+'_resolved',resolved6:p+'_resolved6',subnets:p+'_subnets',subnets6:p+'_subnets6'};},
    args=>args.at(-1)!==missing,(a,b)=>{a.push(...b);return a;},
    {format_ipv6_tproxy_target:(_,p)=>`[::1]:${p}`},
    (_,chain,args)=>{emitted.push({chain,args});return true;},()=>{},()=>{});
  fn('forkop','lan','0x04000000',sections);return emitted;
}
let rules=run();assert.strictEqual(rules.length,8);
for(const {args} of rules) {
  assert(args.includes('0x04000000'),'must require mark');
  const target=args.includes(':17020')||args.includes('[::1]:17020')?'a':'b';
  const other=target==='a'?'b':'a';
  for(const name of [other,'c']) {
    const suffix=args.includes('ip6')?'6':'';
    for(const kind of ['resolved','subnets']) {
      const needle='@forkop_rule_'+name+'_'+kind+suffix;
      const n=args.indexOf(needle);
      assert(n>0 && args[n-1]==='!=',`must exclude ${needle}`);
    }
  }
}
rules=run('forkop_rule_c_resolved');
assert.strictEqual(rules.length,0,'missing competitor set must skip pin');
console.log('PASS: mark, rival resolved and community/IP subnets, missing-set fallback');
