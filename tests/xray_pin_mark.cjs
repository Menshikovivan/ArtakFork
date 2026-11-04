// The resolved-domain pin must not capture packets that nft did not mark for TPROXY.
// Runs the actual ucode rule-builder as JavaScript with nft insertion mocked.
const fs = require('fs');
const assert = require('assert');
const code = fs.readFileSync('forkop/files/usr/lib/nft/apply.uc', 'utf8');
const match = code.match(/function nft_install_resolved_pin_tproxies\([^]*?\n\}/);
assert(match, 'resolved pin builder missing');
const emitted = [];
const build = new Function('engine','xray_constants','length','object_or_empty','as_string',
  'core_ip','nft_insert_rule','log_info','log_debug',
  `${match[0]}\nreturn nft_install_resolved_pin_tproxies;`);
const pin = build({is_xray_primary:()=>true}, {
  section_pin_specs:()=>[{name:'test',port:17020}],
  FAKEIP_INET4_RANGE:'198.18.0.0/15', FAKEIP_INET6_RANGE:'fc00::/18'
}, v=>v.length, v=>v||{}, String,
{format_ipv6_tproxy_target:(_,p)=>`[::1]:${p}`},
(_,chain,args)=>{ emitted.push({chain,args}); return true; }, ()=>{}, ()=>{});
assert(pin('forkop','lan','0x04000000'));
assert.strictEqual(emitted.length,4,'expected IPv4 and IPv6 TCP and UDP pin rules');
for (const {chain,args} of emitted) {
  assert.strictEqual(chain,'proxy');
  const offset = args.findIndex((v,i)=>v==='meta' && args[i+1]==='mark');
  assert(offset >= 0, 'pin must require the routing mark');
  assert.deepStrictEqual(args.slice(offset,offset+5),
    ['meta','mark','&','0x04000000','==']);
  assert.strictEqual(args[offset+5], '0x04000000');
  assert(args.includes('accept'));
}
const caller = code.match(/function nft_add_section_priority_rules_from_sections\([^]*?\n\}/);
assert(caller && caller[0].includes('nft_install_resolved_pin_tproxies(table, interface_set, mark)'),
  'pin builder must use the configured mark rather than a fixed default');
console.log('Resolved pin requires configured TPROXY mark: PASS');
