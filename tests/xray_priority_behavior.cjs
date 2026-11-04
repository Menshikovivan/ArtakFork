// Evaluate rules emitted by the real ucode routing helpers with synthetic inputs.
// This exercises first-match semantics for IPv4/domain rules; it does not emulate nftables.
const fs = require('fs');
const assert = require('assert');
const source = fs.readFileSync('forkop/files/usr/lib/xray/generator.uc', 'utf8');
function fn(name) {
  const found = source.match(new RegExp(`function ${name}\\([^]*?\\n\\}`));
  assert(found, `${name} missing`);
  return found[0].replace(/for \(let section in enabled_sections_any\(\)\)/g,
    'for (let section of enabled_sections_any())');
}
const constants = { FAKEIP_INET4_RANGE:'198.18.0.0/15', FAKEIP_INET6_RANGE:'fc00::/18',
  BLACKHOLE_TAG:'block', FREEDOM_TAG:'direct' };
function generate(sections) {
  const build = new Function('enabled_sections_any', 'apply_section_resolved_pins',
    'section_policy_tproxy_target', 'connections', 'option', 'section_tproxy_target',
    'section_domain_matchers', 'section_ip_matchers', 'list_values', 'engine',
    'ensure_singbox_fullroute_outbound', 'push', 'xray_constants', 'tproxy_inbound_tags',
    'plane_fallback_tag', 'length', 'object_or_empty', `${fn('push_tproxy_rule')}\n${fn('apply_section_tproxy_matchers')}\n${fn('apply_section_tproxy_sources')}\n${fn('apply_primary_tproxy_routes')}\nreturn apply_primary_tproxy_routes;`);
  const apply = build(() => sections, () => {}, s => ({ bypass:{outboundTag:'direct'}, block:{outboundTag:'block'} })[s.action] || null,
    { is_connections_action: a => a === 'connection' }, (s,k,d) => s[k] ?? d,
    (_,s) => ({outboundTag:s.target}), s => s.domains || [], s => s.ips || [],
    (s,k) => s[k] || [], { is_xray_primary: () => false }, () => {},
    (a,v) => a.push(v), constants, () => ['tproxy-in'], () => 'direct',
    value => value.length, value => value || {});
  const config = {routing:{rules:[]}};
  apply(config, []);
  return config.routing.rules;
}
function ipv4(s) { return s.split('.').reduce((a,n) => ((a << 8) | Number(n)) >>> 0, 0); }
function ipMatch(addr, net) {
  if (!addr || net.includes(':')) return false;
  const [network, bits='32'] = net.split('/');
  const mask = Number(bits) === 0 ? 0 : (0xffffffff << (32 - Number(bits))) >>> 0;
  return (ipv4(addr) & mask) === (ipv4(network) & mask);
}
function matches(rule, packet) {
  if (rule.inboundTag && !rule.inboundTag.includes('tproxy-in')) return false;
  if (rule.source && !rule.source.some(net => ipMatch(packet.source, net))) return false;
  if (rule.ip && !rule.ip.some(net => ipMatch(packet.ip, net))) return false;
  if (rule.domain && !rule.domain.some(d => {
    const value = d.replace(/^(full|domain):/, '');
    return packet.domain === value || (d.startsWith('domain:') && packet.domain?.endsWith('.' + value));
  })) return false;
  return true;
}
function route(sections, packet) {
  const rule = generate(sections).find(r => matches(r, packet));
  return rule && (rule.outboundTag || rule.balancerTag);
}
const checks = [
  ['upper fully routed source wins over lower domain', [
    {action:'bypass', fully_routed_ips:['192.0.2.7/32']},
    {action:'block', domains:['full:example.net']}
  ], {source:'192.0.2.7', ip:'203.0.113.8', domain:'example.net'}, 'direct'],
  ['upper domain wins over lower fully routed source', [
    {action:'block', domains:['full:example.net']},
    {action:'bypass', fully_routed_ips:['192.0.2.7/32']}
  ], {source:'192.0.2.7', ip:'203.0.113.8', domain:'example.net'}, 'block'],
  ['unmatched FakeIP remains blocked', [
    {action:'bypass', fully_routed_ips:['192.0.2.7/32']}
  ], {source:'192.0.2.7', ip:'198.18.0.2'}, 'block'],
  ['excluded source must fall through to next domain rule', [
    {action:'block', domains:['full:example.net'], excluded_source_ips:['192.0.2.7/32']},
    {action:'bypass', domains:['full:example.net']}
  ], {source:'192.0.2.7', ip:'203.0.113.8', domain:'example.net'}, 'direct'],
  ['source-limited domain must not match other source', [
    {action:'block', domains:['full:example.net'], source_ip_cidr:['192.0.2.8/32']},
    {action:'bypass', domains:['full:example.net']}
  ], {source:'192.0.2.7', ip:'203.0.113.8', domain:'example.net'}, 'direct']
];
let failed = 0;
for (const [name, sections, packet, expected] of checks) {
  const actual = route(sections, packet);
  if (actual !== expected) { console.error(`FAIL: ${name}: expected ${expected}, got ${actual}`); failed++; }
  else console.log(`PASS: ${name}`);
}
// Exercise the real nft pin builder. A previous section has already accepted a
// fully-routed source into TPROXY; a later section's resolved-domain pin must
// not redirect that source to the later section's dedicated inbound.
const nftSource = fs.readFileSync('forkop/files/usr/lib/nft/apply.uc', 'utf8');
const nftFn = nftSource.match(/function nft_install_resolved_pin_tproxies\([^]*?\n\}/);
assert(nftFn, 'nft pin builder missing');
const nftRules = [];
const pin = new Function('engine', 'xray_constants', 'length', 'object_or_empty', 'as_string',
  'core_ip', 'nft_insert_rule', 'log_info', 'log_debug',
  `${nftFn[0]}\nreturn nft_install_resolved_pin_tproxies;`)(
  {is_xray_primary:() => true},
  {section_pin_specs:() => [{name:'later', port:17020}], FAKEIP_INET4_RANGE:'198.18.0.0/15', FAKEIP_INET6_RANGE:'fc00::/18'},
  v => v.length, v => v || {}, String, {format_ipv6_tproxy_target:(_,port) => `[::1]:${port}`},
  (_,chain,args) => { nftRules.unshift({chain,args}); return true; }, () => {}, () => {});
pin('forkop', 'lan');
const tcpPin = nftRules.find(r => r.args.includes('@forkop_rule_later_resolved') && r.args.includes('tcp'));
assert(tcpPin, 'expected later section TCP pin');
// A source constraint is necessary for this pin to distinguish this case; a
// destination-only pin matches both an earlier fully-routed source and others.
if (!tcpPin.args.includes('saddr')) {
  console.error('FAIL: later resolved-domain nft pin does not preserve earlier fully-routed source priority');
  failed++;
} else console.log('PASS: resolved-domain nft pin has source-aware constraints');
if (failed) process.exitCode = 1;
