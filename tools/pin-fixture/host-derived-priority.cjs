// Unit exercise of the actual generated Xray rule functions, with ucode builtins stubbed.
const fs = require('fs');
const assert = require('assert');
const src = fs.readFileSync('forkop/files/usr/lib/xray/generator.uc','utf8');
const f = name => {
  let m = src.match(new RegExp(`function ${name}\\([^]*?\\n\\}`));
  assert(m, name + ' missing');
  // ucode for-in iterates values; only translate loops whose RHS is an array.
  return m[0].replace(/for \(let (section|value|key|host|ip) in /g, 'for (let $1 of ')
    .replace('for (let key of extra)', 'for (let key in extra)');
};
const source = ['section_ip_matchers','section_host_ip_matchers','push_tproxy_rule',
  'apply_section_tproxy_matchers','apply_section_tproxy_host_ips','apply_primary_tproxy_routes']
  .map(f).join('\n');
const constants = { FAKEIP_INET4_RANGE:'198.18.0.0/15', FAKEIP_INET6_RANGE:'fc00::/18',
  BLACKHOLE_TAG:'block', FREEDOM_TAG:'direct' };
function generate(sections) {
  const factory = new Function('csv_values','list_values','section_converted_lists',
    'push_unique','usable_xray_matchers','engine','section_user_domain_hosts','hostresolve',
    'type','match','object_or_empty','tproxy_inbound_tags','push','length',
    'apply_section_resolved_pins','enabled_sections_any','section_policy_tproxy_target',
    'connections','option','section_tproxy_target','section_domain_matchers',
    'apply_section_tproxy_sources','plane_fallback_tag','xray_constants',
    `${source}\nreturn apply_primary_tproxy_routes;`);
  const apply = factory((s,k) => s[k] || [], (s,k) => s[k] || [], s => ({ips:s.communityIps || []}),
    (a,v) => { if (!a.includes(v)) a.push(v); }, x => x,
    {is_xray_primary:()=>true}, s => s.hosts || [],
    {resolve_hosts: hosts => Object.fromEntries(hosts.map(h=>[h,['203.0.113.8']]))},
    v=>Array.isArray(v)?'array':typeof v, (s,re)=>s.match(re), o=>o||{},
    ()=>['tproxy-in'], (a,v)=>a.push(v), v=>v.length, ()=>{}, ()=>sections,
    ()=>null, {is_connections_action: a=>a==='connection'}, (s,k,d)=>s[k]??d,
    (_,s)=>({outboundTag:s.name}), s=>s.domains||[], ()=>{}, ()=> 'direct',constants);
  const config={routing:{rules:[]}}; apply(config, []); return config.routing.rules;
}
function first(rules, domain, ip) {
  return rules.find(r => (!r.domain || r.domain.includes('full:'+domain)) &&
    (!r.ip || r.ip.includes(ip) || (ip.startsWith('198.18.') && r.ip.includes('198.18.0.0/15'))));
}
const sections = [
  {name:'A',action:'connection',domains:['full:a.test'],hosts:['a.test']},
  {name:'B',action:'connection',domains:['full:b.test'],hosts:['b.test']}
];
let rules=generate(sections);
assert.strictEqual(first(rules,'a.test','203.0.113.8').outboundTag,'A');
assert.strictEqual(first(rules,'b.test','203.0.113.8').outboundTag,'B',
  'B sniffed domain must beat A host-derived shared IP');
assert.strictEqual(first(rules,'unknown.test','198.18.0.2').outboundTag,'block',
  'unknown fakeip must stay blocked');
assert.strictEqual(first(rules,'unknown.test','203.0.113.8').outboundTag,'A',
  'host-IP fallback remains ordered and ambiguous without a domain');
sections[0].ip_cidr=['203.0.113.8'];
rules=generate(sections);
assert.strictEqual(first(rules,'b.test','203.0.113.8').outboundTag,'A',
  'explicit IP retains section priority');
delete sections[0].ip_cidr;
sections[0].communityIps=['203.0.113.8'];
rules=generate(sections);
assert.strictEqual(first(rules,'b.test','203.0.113.8').outboundTag,'A',
  'community IP retains section priority');
console.log('PASS: sniffed domains precede host-derived IP; explicit IP priority retained');
